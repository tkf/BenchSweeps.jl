module BenchSweeps

export BenchSweepGroup, defsweep!, @defsweep!

using BenchmarkTools
using MacroTools: @capture
using Statistics

include("iterutils.jl")

const array_names = (:gctime, :time)
const reserved_names = (array_names..., :alloc, :memory, :name)

const NameType = Any

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
    for args in Iterators.product([group.axes[k] for k in axes_keys]...)
        suite[args] = f(args...)
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

function astable(group::BenchSweepGroup; agg = median)
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
    colnames = [:name; axes_keys; [:allocs, :gctime, :memory, :time]]
    coleltypes = [NameType; eltypes; [Int, Float64, Int, Float64]]
    rowtype = NamedTuple{Tuple(colnames), Tuple{coleltypes...}}

    # name -> axes_key -> position in sorted axes_keys
    keytopos = Dict{NameType,Dict{Symbol,Int}}()
    for name in keys(group.bench)
        keytopos[name] = Dict()
        for k in group.sweeps[name]
            keytopos[name][k] = findfirst(isequal(k), axes_keys)
        end
    end

    return TypedGenerator{rowtype}(SizedIterator(
        (name, trial)
        for name in keys(group.bench) for trial in group.bench[name]
    )) do (name, trial)
        tkey, tval = trial
        estimate = agg(tval)

        vals = Vector(undef, length(group.axes))
        fill!(vals, missing)
        for (k, v) in zip(group.sweeps[name], tkey)
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

end # module
