function murmur64(h::UInt64)
	h ⊻= h >> 33
	h *= 0xff51afd7ed558ccd
	h ⊻= h >> 33
	h *= 0xc4ceb9fe1a85ec53
	h ⊻= h >> 33
	return h
end


# returns random number, modifies the seed
function splitmix64(seed::UInt64)
	seed += 0x9e3779b97f4a7c15
	z = (seed ⊻ (seed >> 30)) * 0xbf58476d1ce4E5b9
	z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
	return seed, z ⊻ (z >> 31)
end


function mixsplit(key::UInt64, seed::UInt64)
	return murmur64(key + seed)
end


function rotl64(n::UInt64, c::Int)
	return (n << UInt64(c & 63)) | (n >> UInt64((-c) & 63))
end


function reduce(hash, n::UInt32)
	# http://lemire.me/blog/2016/06/27/a-fast-alternative-to-the-modulo-reduction/
	return UInt32((UInt64(hash) * UInt64(n)) >> 32)
end


# xor fold
function fingerprint(hash::UInt64)
	hash = (hash >> 32) ⊻ ((hash << 32) >> 32) # fold to 32 bits
	hash = (hash >> 16) ⊻ ((hash << 48) >> 48) # fold to 16 bits
	hash = (hash >> 8) ⊻ ((hash << 56) >> 56) # fold to 8 bits
	return UInt8(hash)
end


function mod3(x)
	if (x > 2)
	    x -= 3
    end
	return x
end


function binary_fuse_mulhi(a::UInt64, b::UInt64)
    return UInt64((UInt128(a) * UInt128(b)) >> 64)
end

