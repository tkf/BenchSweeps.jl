module TestBenchSweeps

include("preamble.jl")

@testset "$file" for file in [
        "test_smoke.jl",
        ]
    include(file)
end

end  # module
