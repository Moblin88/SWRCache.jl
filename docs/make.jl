using Documenter
using SWRCache

makedocs(
    sitename = "SWRCache.jl",
    modules = [SWRCache],
    format = Documenter.HTML(),
    repo = Documenter.Remotes.GitHub("Moblin88", "SWRCache.jl"),
    pages = [
        "Home" => "index.md",
    ],
)

deploydocs(
    repo = "github.com/Moblin88/SWRCache.jl.git",
    devbranch = "main",
)
