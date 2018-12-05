using Documenter, BenchSweeps

makedocs(;
    modules=[BenchSweeps],
    format=:html,
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/tkf/BenchSweeps.jl/blob/{commit}{path}#L{line}",
    sitename="BenchSweeps.jl",
    authors="Takafumi Arakaki",
    assets=[],
)

deploydocs(;
    repo="github.com/tkf/BenchSweeps.jl",
    target="build",
    julia="1.0",
    deps=nothing,
    make=nothing,
)
