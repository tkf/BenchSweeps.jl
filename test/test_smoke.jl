module TestSmoke

include("preamble.jl")

using LinearAlgebra
using DataFrames: DataFrame

suite = BenchSweepGroup()
suite.axes[:n] = 2 .^ (4:5)
suite.axes[:m] = 2 .^ (4:5)

@defsweep! for n in suite["matrix-vector"]
    @benchmarkable mul!(y, A, x) setup=begin
        y = zeros($n)
        A = rand($n, $n)
        x = rand($n)
    end
end

@defsweep! for (n, m) in suite["matrix-matrix"]
    @benchmarkable mul!(Y, A, X) setup=begin
        Y = zeros($n, $m)
        A = rand($n, $n)
        X = rand($n, $m)
    end
end

# Options for `tune!` is for trying to make runtime short:
tune!(suite; maxevals=1, seconds=0.1, samples=1)
results = run(suite)

for row in BenchSweeps.astable(results)
    @test row isa NamedTuple
end

for row in BenchSweeps.asrawtable(results)
    @test row isa NamedTuple
end

for row in BenchSweeps.astrialtable(results)
    @test row isa NamedTuple
    @test row.trial isa BenchmarkTools.Trial
end

@test DataFrame(results) isa DataFrame
@test DataFrame(results, :raw) isa DataFrame
@test DataFrame(results, :trial) isa DataFrame

buf = IOBuffer()
@test BenchSweeps.save(buf, results) isa Nothing
seekstart(buf)
@test (global recovered = BenchSweeps.load(buf)) isa BenchSweepGroup

@test mktempdir() do dir
    filename = joinpath(dir, "results.json")
    BenchSweeps.save(filename, results)
    BenchSweeps.load(filename) isa BenchSweepGroup
end

@test DataFrame(recovered) isa DataFrame
@test DataFrame(recovered, :raw) isa DataFrame
@test DataFrame(recovered, :trial) isa DataFrame

end  # module
