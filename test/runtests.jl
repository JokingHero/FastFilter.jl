using Test
using FastFilter
using Random

@testset "binaryfusefilter.jl" begin
    n = 10
    items = rand(UInt64, n)
    filter = BinaryFuseFilter(items)

    @testset "construct" begin
        @test length(filter) == n
        for i in items
            @test i in filter 
        end
    end
end