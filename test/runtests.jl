using Test
using FastFilter
using Random

@testset "binaryfusefilter.jl" begin
    n = Int(1e5)
    items = rand(UInt64, n)
    filter = BinaryFuseFilter(items)

    @testset "true positives should always be inside" begin
        for i in items
            @test i in filter 
        end
    end

    not_in_items = rand(UInt64, Int(1e6))
    not_in_items = setdiff(not_in_items, items)

    @testset "false positives should be below threshold" begin
        fp = 0
        for i in not_in_items
            fp += i in filter
        end
        @test fp/length(not_in_items) < 0.004
    end

    filter2 = BinaryFuseFilter(items; seed = UInt64(42))
    @testset "seed should influence construction" begin
        for i in items
            @test i in filter2
        end

        fp = 0
        for i in not_in_items
            fp += i in filter
        end
        @test fp/length(not_in_items) < 0.004

        # and finally combined filters should have lower fp
        # verified twice in two seed
        fp2 = 0
        for i in not_in_items
            fp2 += (i in filter) & (i in filter2)
        end

        @test fp2 < fp 
    end
end