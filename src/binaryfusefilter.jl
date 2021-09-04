struct BinaryFuseFilter
    seed::UInt64
    segment_length::UInt32
    segment_length_mask::UInt32
    segment_count::UInt32
    segment_count_length::UInt32
	array_length::UInt32
    fingerprints::Vector{UInt8}
    n_keys::UInt32
end


function calculate_segment_length(arity::UInt32, n_keys::UInt32)
	# These parameters are very sensitive. Replacing 'floor' by 'round' can
    # substantially affect the construction time. 
	if arity == 3
		return UInt32(1) << Int(floor(log(Float64(n_keys)) / log(3.33) + 2.25))
	elseif arity == UInt32(4)
		return UInt32(1) << Int(floor(log(Float64(n_keys)) / log(2.91) - 0.5))
	else
		return UInt32(65536)
    end
end


function calculate_size_factor(arity::UInt32, n_keys::UInt32)
	if arity == 3
		return Float64(max(1.125, 0.875 + 0.25 * log(1000000)/log(Float64(n_keys))))
	elseif arity == 4
		return Float64(max(1.075, 0.77 + 0.305 * log(600000)/log(Float64(n_keys))))
	else
		return Float64(2.0)
	end
end


function get_hash_from_hash(
	hash::UInt64, 
	segment_count_length::UInt32, 
	segment_length::UInt32, 
	segment_length_mask::UInt32)
	hi = binary_fuse_mulhi(hash, UInt64(segment_count_length))
	h0 = UInt32(hi & 0xFFFFFFFF)
	h1 = h0 + segment_length
	h2 = h1 + segment_length
	h1 ⊻= UInt32((hash >> 18) & segment_length_mask)
	h2 ⊻= UInt32(hash & segment_length_mask)
	return h0, h1, h2
end


function BinaryFuseFilter(keys::Vector{UInt64}; seed = UInt64(0x726b2b9d438b9d4d), max_iterations = 100)
	n_keys = UInt32(length(keys))
	if n_keys == 0
		throw("No keys for construction.")
	end

	arity = UInt32(3)
	segment_length = calculate_segment_length(arity, n_keys)
	if (segment_length > 262144)
    	segment_length = UInt32(262144)
    end

	segment_length_mask = UInt32(segment_length - 1)
	size_factor = calculate_size_factor(arity, n_keys)
	capacity = UInt32(round(Float64(n_keys) * size_factor))
	segment_count = UInt32(ceil((capacity + segment_length - 1) / segment_length - (arity - 1)))
	array_length = (segment_count + arity - 1) * segment_length
	segment_count = UInt32(ceil((array_length + segment_length - 1)/segment_length))
	if (segment_count <= (arity - 1))
		segment_count = 1
	else
		segment_count = segment_count - (arity - 1)
    end
	array_length = (segment_count + arity - 1) * segment_length

	segment_count_length = UInt32(segment_count * segment_length)
	fingerprints = zeros(UInt8, array_length)

	# Adding elements
	rngcounter = seed
	seed, rngcounter = splitmix64(rngcounter)
	capacity = UInt32(array_length)

	alone = zeros(UInt32, capacity)
	# the lowest 2 bits are the h index (0, 1, or 2)
	# so we only have 6 bits for counting;
	# but that's sufficient
	t2count = zeros(UInt8, capacity)
	reverseH = zeros(UInt8, n_keys)
	t2hash = zeros(UInt64, capacity)
	reverseOrder = zeros(UInt64, n_keys + 1)
	reverseOrder[n_keys + 1] = 1 # uneccessary item serving as a blocker

	# the array h0, h1, h2, h0, h1, h2
	h012 = zeros(UInt32, 5)
	iterations = 0

	blockBits = 1
	while UInt32(1 << blockBits) < segment_count
		blockBits += 1
	end
	block = 1 << blockBits

	while true
		iterations += 1
		print(iterations)
		print("\n")
		if iterations > max_iterations
			throw("Too many iterations, you probably have duplicate keys.")
		end

		startPos = zeros(UInt32, block)
		for i in 1:length(startPos)
			# important: we do not want i * n_keys to overflow!!!
			# in java we have (int) ((long) i * size / block)
			startPos[i] = UInt32(((UInt64(i - 1) * UInt64(n_keys)) >> blockBits))
		end

		# counting sort to the h0 region
		maskblock = block - 1
		for key in keys
			hash = mixsplit(key, seed)
			# this is java >>> shifted values are zeros
			# java (int) (hash >>> (64 - blockBits))
			segment_index = hash >> (64 - blockBits)
			while reverseOrder[startPos[segment_index + 1] + 1] != 0
				segment_index += 1
				segment_index &= maskblock
			end
			reverseOrder[startPos[segment_index + 1] + 1] = hash
			startPos[segment_index + 1] += 1
		end


		# We can then scan through the partially sorted keys and update a temporary array of counters—
        # such an array tells us how many keys map to a given location. Because the keys are sorted
        # by region, a forward pass through the keys tends to access the counters in a forward manner,
        # thus reducing the number of cache misses compared to a random approach.
		error = 0
		for i in UInt32.(1:n_keys)
			hash = reverseOrder[i]
			index1, index2, index3 = get_hash_from_hash(
				hash, segment_count_length, segment_length, segment_length_mask)
			t2count[index1 + 1] += 4
			t2hash[index1 + 1] ⊻= hash
			t2count[index2 + 1] += 4
			t2count[index2 + 1] ⊻= 1
			t2hash[index2 + 1] ⊻= hash
			t2count[index3 + 1] += 4
			t2count[index3 + 1] ⊻= 2
			t2hash[index3 + 1] ⊻= hash
			if t2count[index1 + 1] < 4 # no clue what is being checked here...
				error = 1
			end
			if t2count[index2 + 1] < 4
				error = 1
			end
			if t2count[index3 + 1] < 4
				error = 1
			end
		end
		if error == 1
			continue
		end

		Qsize = 0
		# We scan the array of counters to identify the locations corresponding to a single set entry.
        # The entries are added to a stack. Since we scan forward, the later entries in the stack tend to
        # correspond to later locations.
		for i in UInt32.(1:capacity) # capacity != alone size??...
			alone[Qsize + 1] = i - 1
			if (t2count[i] >> 2) == 1
				Qsize += 1
			end
		end
		stacksize = UInt32(0)
		while Qsize > 0
			Qsize -= 1
			index = alone[Qsize + 1]
			if (t2count[index + 1] >> 2) == 1
				hash = t2hash[index + 1]
				found = t2count[index + 1] & 3
				reverseH[stacksize + 1] = found
				reverseOrder[stacksize + 1] = hash
				stacksize += 1

				index1, index2, index3 = get_hash_from_hash(
					hash, segment_count_length, segment_length, segment_length_mask)

				h012[2] = index2
				h012[3] = index3
				h012[4] = index1
				h012[5] = h012[2]

				other_index1 = h012[found + 1]
				alone[Qsize + 1] = other_index1
				if (t2count[other_index1 + 1] >> 2) == 2
					Qsize += 1
				end
				t2count[other_index1 + 1] -= 4
				t2count[other_index1 + 1] ⊻= mod3(found + 1)
				t2hash[other_index1 + 1] ⊻= hash

				other_index2 = h012[found + 2]
				alone[Qsize + 1] = other_index2
				if (t2count[other_index2 + 1] >> 2) == 2
					Qsize += 1
				end
				t2count[other_index2 + 1] -= 4
				t2count[other_index2 + 1] ⊻= mod3(found + 2)
				t2hash[other_index2 + 1] ⊻= hash
			end
		end

		if stacksize == n_keys
			break
		end
		for i in UInt32.(1:n_keys)
			reverseOrder[i] = 0
		end
		for i in UInt32(1:capacity)
			t2count[i] = 0
			t2hash[i] = 0
		end
		rngcounter, seed = splitmix64(rngcounter)
	end

	# Finally, starting from the latter stack, we can construct the binary fuse filter, by making sure
    # that the bitwise exclusive or of the three locations map to the fingerprint of the matched
    # entries. By construction, we tend to go from locations that are at the beginning of the array,
    # working toward the end of the array.
	for i in n_keys:-1:1
		# the hash of the key we insert next
		hash = reverseOrder[i]
		xor2 = UInt8(fingerprint(hash))
		index1, index2, index3 = get_hash_from_hash(
			hash, segment_count_length, segment_length, segment_length_mask)
		found = reverseH[i]
		h012[1] = index1
		h012[2] = index2
		h012[3] = index3
		h012[4] = h012[1]
		h012[5] = h012[2]
		fingerprints[h012[found + 1] + 1] = xor2 ⊻ fingerprints[h012[found + 2] + 1] ⊻ fingerprints[h012[found + 3] + 1]
	end

	return BinaryFuseFilter(
		seed,
		segment_length, segment_length_mask,
    	segment_count, segment_count_length,
		array_length,
    	fingerprints, n_keys)
end


function Base.summary(io::IO, filter::BinaryFuseFilter)
    print(io, "BinaryFuseFilter with $(filter.n_keys) keys and seed $(filter.seed).")
end
Base.show(io::IO, filter::BinaryFuseFilter) = summary(io, filter)


function Base.in(key, filter::BinaryFuseFilter)
    hash = mixsplit(key, filter.seed)
    f = UInt8(fingerprint(hash))
	h0, h1, h2 = get_hash_from_hash(
		hash, filter.segment_count_length, filter.segment_length, filter.segment_length_mask)
	f ⊻= (filter.fingerprints[h0] ⊻ filter.fingerprints[h1] ⊻ filter.fingerprints[h2])
	return f == 0
end