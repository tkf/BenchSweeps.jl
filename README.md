# BenchSweeps

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://tkf.github.io/BenchSweeps.jl/stable)
[![Latest](https://img.shields.io/badge/docs-latest-blue.svg)](https://tkf.github.io/BenchSweeps.jl/latest)
[![Build Status](https://travis-ci.com/tkf/BenchSweeps.jl.svg?branch=master)](https://travis-ci.com/tkf/BenchSweeps.jl)
[![Codecov](https://codecov.io/gh/tkf/BenchSweeps.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/tkf/BenchSweeps.jl)
[![Coveralls](https://coveralls.io/repos/github/tkf/BenchSweeps.jl/badge.svg?branch=master)](https://coveralls.io/github/tkf/BenchSweeps.jl?branch=master)

BenchSweeps.jl wraps [BenchmarkTools.jl] to:

* Setup grid of parameters and define benchmarks for all combinations
  of them.  Those parameters and defined benchmarks are bundled
  together by `BenchSweepGroup`.
* Access benchmark data using dataframe/table-like interface.
  `BenchSweepGroup` supports [Tables.jl] and [IterableTables.jl] API
  and more controllable interface for [DataFrames.jl].
* Save/load `BenchSweepGroup` to/from a JSON file.

[BenchmarkTools.jl]: https://github.com/JuliaCI/BenchmarkTools.jl
[Tables.jl]: https://github.com/JuliaData/Tables.jl
[IterableTables.jl]: https://github.com/queryverse/IterableTables.jl
[DataFrames.jl]: https://github.com/JuliaData/DataFrames.jl

### Usage:

```julia
using BenchSweeps
using LinearAlgebra

suite = BenchSweepGroup()
suite.axes[:n] = 2 .^ (2:5)
suite.axes[:m] = 2 .^ (2:5)

@defsweep! for (n, m) in suite["matrix-matrix"]
    @benchmarkable mul!(Y, A, X) setup=begin
        Y = zeros($n, $m)
        A = rand($n, $n)
        X = rand($n, $m)
    end
end

results = run(suite)

using DataFrames
df = DataFrame(results)  # now analyze the benchmark
```
