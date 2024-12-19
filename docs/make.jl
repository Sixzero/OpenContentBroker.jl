using OpenContentBroker
using Documenter

DocMeta.setdocmeta!(OpenContentBroker, :DocTestSetup, :(using OpenContentBroker); recursive=true)

makedocs(;
    modules=[OpenContentBroker],
    authors="SixZero <havliktomi@hotmail.com> and contributors",
    sitename="OpenContentBroker.jl",
    format=Documenter.HTML(;
        canonical="https://sixzero.github.io/OpenContentBroker.jl",
        edit_link="master",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/sixzero/OpenContentBroker.jl",
    devbranch="master",
)
