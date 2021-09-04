__precompile__(true)

module FastFilter

using Random
include("utils.jl")
include("binaryfusefilter.jl")
export BinaryFuseFilter

end
