module BenchSweeps

export BenchSweepGroup, defsweep!, @defsweep!

using Reexport: @reexport
using Requires: @require

@reexport using BenchmarkTools
using MacroTools: @capture
using Statistics

include("iterutils.jl")

const array_names = (:gctime, :time)
const reserved_names = (array_names..., :alloc, :memory, :trial, :name)

const NameType = Any

"""
    BenchSweepGroup()

# Examples
```jldoctest
julia> suite = BenchSweepGroup();

julia> suite.axes[:n] = 2 .^ (0:2:10);

julia> suite.axes[:f] = [:rand, :randn];

julia> using Random

julia> @defsweep! for (n, f) in suite["sort"]
           @benchmarkable sort(x) setup=(x = Random.\$f(\$n))
       end;
```

# Internals
- `axes::Dict{Symbol,Vector}`: A mapping `axis key -> axis values`.
- `sweeps::Dict{Symbol,Vector{Symbol}}`: A mapping from benchmark group
  name to a list of axis keys.
- `bench::BenchmarkGroup`: A mapping `name -> coord -> benchark or trial`.
  For a `name`, `coord` is a `n`-tuple where `n = length(sweeps[name])`.
  The `i`-th element of `coord` is taken from `axes[sweeps[name][i]]`.
"""
struct BenchSweepGroup
    axes::Dict{Symbol,Vector}
    sweeps::Dict{NameType,Vector{Symbol}}
    bench::BenchmarkGroup
end

BenchSweepGroup() = BenchSweepGroup(Dict(), Dict(), BenchmarkGroup())

function check_axes_key(axes_keys)
    for key in axes_keys
        @assert key ∉ reserved_names
    end
end

function defsweep!(f::Function, group::BenchSweepGroup,
                   name::NameType,
                   axes_keys::Vector{Symbol})
    check_axes_key(axes_keys)
    @assert !haskey(group.sweeps, name)
    group.sweeps[name] = axes_keys
    group.bench[name] = suite = BenchmarkGroup()
    for coord in Iterators.product([group.axes[k] for k in axes_keys]...)
        suite[coord] = f(coord...)
    end
    return suite
end

macro defsweep!(for_loop)
    if !@capture(for_loop, for axes_keys_ in group_[name_]; body_; end)
        error("Unsupported syntax:\n", for_loop)
    end
    if axes_keys isa Symbol
        axes_keys = Symbol[axes_keys]
    elseif axes_keys isa Expr
        axes_keys = Symbol.(axes_keys.args)
    else
        error("Unsupported `axes_keys` expression:\n", axes_keys)
    end
    esc(quote
        $defsweep!($group, $name, $axes_keys) do $(axes_keys...)
            $body
        end
    end)
end

BenchmarkTools.tune!(group::BenchSweepGroup, args...; kwargs...) =
    tune!(group.bench, args...; kwargs...)

Base.run(group::BenchSweepGroup, args...; kwargs...) =
    BenchSweepGroup(group.axes,
                    group.sweeps,
                    run(group.bench, args...; kwargs...))

"""
    BenchSweeps.astable(group, [agg = median])
    BenchSweeps.asrawtable(group)
    BenchSweeps.astrialtable(group)

Convert `group::BenchSweepGroup` to an iterator of `NamedTuple`s.
This is exposed as Tables.jl and TableTraits.jl interfaces.
This function can be invoked by `DataFrames.DataFrame` as well.

# Arguments

- `agg::Union{Function,Symbol}`: "aggregation" function.  Any
  function that consumes `BenchmarkTools.Trial` and yields
  `BenchmarkTools.TrialEstimate` can be passed (e.g., `median`,
  `minimum`, `mean`, etc.).

  If it is `:raw` then this function returns a longer iterator whose
  element is an individual sample.  `asrawtable(group)` is an alias
  for `astable(group, :raw)`.

  If it is `:trial` then each row includes `BenchmarkTools.Trial`
  object in `:trial` column.  This is useful for extracting trial
  results and run `judge` on them.  `astrialtable(group)` is an alias
  for `astable(group, :trial)`.

"""
(astable, asrawtable, astrialtable)

function astable(group::BenchSweepGroup, agg = median)
    if agg === :raw
        asrawtable(group)
    elseif agg === :trial
        astrialtable(group)
    elseif agg isa Union{Symbol, AbstractString}
        # capture a typo here:
        error("`agg` must be `:raw`, `:trial` or a callable; got: ", agg)
    else
        # otherwise let's hope that `agg` is a callable
        _astable(group, agg)
    end
end

asrawtable(group::BenchSweepGroup) = _astable(group, nothing)

function _preprocess_table(group)
    axes_keys = sort(collect(keys(group.axes)))
    eltypes = [
        let T = eltype(group.axes[key])
            if T === Any
                T
            elseif all(axs -> T in axs, values(group.sweeps))
                T
            else
                Union{Missing, T}
            end
        end for key in axes_keys
    ]

    # name -> coord -> position in sorted axes_keys
    keytopos = Dict{NameType,Dict{Symbol,Int}}()
    for name in keys(group.bench)
        keytopos[name] = Dict()
        for k in group.sweeps[name]
            keytopos[name][k] = findfirst(isequal(k), axes_keys)
        end
    end

    return (axes_keys, eltypes, keytopos)
end

function _astable(group::BenchSweepGroup, agg)
    axes_keys, eltypes, keytopos = _preprocess_table(group)
    colnames = [:name; axes_keys; [:allocs, :gctime, :memory, :time]]
    coleltypes = [NameType; eltypes; [Int, Float64, Int, Float64]]
    rowtype = NamedTuple{Tuple(colnames), Tuple{coleltypes...}}

    if agg !== nothing
        return TypedGenerator{rowtype}(SizedIterator(
            (name, coord, trial)
            for name in keys(group.bench) for (coord, trial) in group.bench[name]
        )) do (name, coord, trial)
            estimate = agg(trial)

            vals = Vector(undef, length(group.axes))
            fill!(vals, missing)
            for (k, v) in zip(group.sweeps[name], coord)
                vals[keytopos[name][k]] = v
            end

            return rowtype((
                name,
                vals...,
                estimate.allocs,
                estimate.gctime,
                estimate.memory,
                estimate.time,
            ))
        end
    else
        return TypedGenerator{rowtype}(SizedIterator(
            (name, coord, trial, time, gctime)
            for name in keys(group.bench)
            for (coord, trial) in group.bench[name]
            for (time, gctime) in zip(trial.times, trial.gctimes)
        )) do (name, coord, trial, time, gctime)

            vals = Vector(undef, length(group.axes))
            fill!(vals, missing)
            for (k, v) in zip(group.sweeps[name], coord)
                vals[keytopos[name][k]] = v
            end

            return rowtype((
                name,
                vals...,
                trial.allocs,
                gctime,
                trial.memory,
                time,
            ))
        end
    end
end

function astrialtable(group::BenchSweepGroup)
    axes_keys, eltypes, keytopos = _preprocess_table(group)
    colnames = [:name; axes_keys; [:trial]]
    coleltypes = [NameType; eltypes; [BenchmarkTools.Trial]]
    rowtype = NamedTuple{Tuple(colnames), Tuple{coleltypes...}}

    return TypedGenerator{rowtype}(SizedIterator(
        (name, coord, trial)
        for name in keys(group.bench) for (coord, trial) in group.bench[name]
    )) do (name, coord, trial)

        vals = Vector(undef, length(group.axes))
        fill!(vals, missing)
        for (k, v) in zip(group.sweeps[name], coord)
            vals[keytopos[name][k]] = v
        end

        return rowtype((
            name,
            vals...,
            trial,
        ))
    end
end

function Base.show(io::IO, ::MIME"text/plain", group::BenchSweepGroup)
    println(io, "BenchSweepGroup with ", length(group.axes), " axes")
    show(io, MIME("text/plain"), group.axes)
    println(io)
    show(io, MIME("text/plain"), group.bench)
end

function Base.show(io::IO, group::BenchSweepGroup)
    print(io, "BenchSweepGroup with ", length(group.axes), " axes")
    return nothing
end


import Tables
Tables.istable(::Type{<:BenchSweepGroup}) = true
Tables.rowaccess(::Type{<:BenchSweepGroup}) = true
Tables.rows(group::BenchSweepGroup) = astable(group)

import TableTraits
import IteratorInterfaceExtensions
TableTraits.isiterabletable(::BenchSweepGroup) = true
IteratorInterfaceExtensions.getiterator(group::BenchSweepGroup) = astable(group)

function __init__()
    @require DataFrames="a93c6f00-e57d-5684-b7b6-d8193f3e46c0" begin
        """
            DataFrame(group::BenchSweepGroup, [agg = median])

        A shorthand for calling `DataFrame(BenchSweeps.astable(group, agg))`.

        See also: [`BenchSweeps.astable`](@ref).
        """
        DataFrames.DataFrame(group::BenchSweepGroup, agg = median) =
            DataFrames.DataFrame(astable(group, agg))
    end
end

end # module
