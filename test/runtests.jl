using Test
using FastFilter
using Random

utypes = [UInt8, UInt16, UInt32]
error_rates = [0.005, 1.7e-5, 2.33e-10]
rng = MersenneTwister(42)

for i in eachindex(utypes)
    @testset "binaryfusefilter.jl " begin

        @testset "Can be build with stupid small number of items" begin
            filter = BinaryFuseFilter{utypes[i]}([UInt64(1)])
            @test UInt64(1) in filter
        end

        n = Int(230e6)
        items = rand(rng, UInt64, n)
        filter = BinaryFuseFilter{utypes[i]}(items)
    
        @testset "true positives should always be inside" begin
            for i in items
                @test i in filter 
            end
        end
    
        not_in_items = rand(rng, UInt64, Int(1e6))
        not_in_items = setdiff(not_in_items, items)
    
        @testset "false positives should be below threshold" begin
            fp = 0
            for i in not_in_items
                fp += i in filter
            end
            @test fp/length(not_in_items) < error_rates[i]
        end
    
        filter2 = BinaryFuseFilter{utypes[i]}(items; seed = UInt64(42))
        @testset "seed should influence construction" begin
            for i in items
                @test i in filter2
            end
    
            fp = 0
            for i in not_in_items
                fp += i in filter
            end
            @test fp/length(not_in_items) < error_rates[i]
            println("False positive rate for " * string(utypes[i]) * 
                " filter: " * string(fp/length(not_in_items)))
    
            # and finally combined filters should have lower fp
            fp2 = 0
            for i in not_in_items
                fp2 += (i in filter) & (i in filter2)
            end
    
            @test fp2 <= fp
        end
    end
end
