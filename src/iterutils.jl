@inline function delegate_iterate(make_iterable, state=nothing)
    if state === nothing
        it = make_iterable()
        y = iterate(it)
    else
        it, itstate = state
        y = iterate(it, itstate)
    end
    y === nothing && return nothing
    return (y[1], (it, y[2]))
end


"""
    TypedGenerator{T}(f, iter)
    TypedGenerator(T, f, iter)

Like `Base.Generator` but with configurable `eltype`.
"""
struct TypedGenerator{T,I,F}
    f::F
    iter::I
end

TypedGenerator{T}(f::F, iter::I) where {T, I, F} = TypedGenerator{T,I,F}(f, iter)
TypedGenerator(T::Type, f, iter) = TypedGenerator{T}(f, iter)

Base.eltype(::Type{<:TypedGenerator{T}}) where {T} = T
Base.length(g::TypedGenerator) = length(g.iter)
Base.size(g::TypedGenerator) = size(g.iter)
Base.axes(g::TypedGenerator) = axes(g.iter)
Base.ndims(g::TypedGenerator) = ndims(g.iter)
Base.IteratorSize(::Type{<:TypedGenerator{T,I}}) where {T,I} =
    Base.IteratorSize(I)
Base.IteratorEltype(::Type{<:TypedGenerator}) = Base.HasEltype()

Base.iterate(g::TypedGenerator, state=nothing) = delegate_iterate(state) do
    Base.Generator(g.f, g.iter)
end


"""
    SizedIterator(iter, [length])

Wrap `iter` in an iterator which has length.
"""
struct SizedIterator{I}
    iter::I
    length::Int
end

function SizedIterator(iter)
    length = sum(1 for _ in iter)
    return SizedIterator(iter, length)
end

Base.eltype(::Type{SizedIterator{I}}) where {I} = Base.eltype(I)
Base.length(g::SizedIterator) = g.length
Base.IteratorSize(::Type{<:SizedIterator}) = Base.HasLength()
Base.IteratorEltype(::Type{SizedIterator{I}}) where {I} = Base.IteratorEltype(I)

Base.iterate(g::SizedIterator, state=nothing) = delegate_iterate(state) do
    g.iter
end
