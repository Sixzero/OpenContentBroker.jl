using ToolCallFormat: @deftool

# Lazy-initialized adapter (reads ENV at first use, not precompile time)
const _google_search_adapter_ref = Ref{Union{Nothing,GoogleAdapter}}(nothing)
function GOOGLE_SEARCH_ADAPTER()
    _google_search_adapter_ref[] === nothing && (_google_search_adapter_ref[] = GoogleAdapter())
    _google_search_adapter_ref[]
end

@deftool "Search with Google" function google_search("Search query" => query::String, "Instructions for the summarizer: what to focus on, extract, or compare" => prompt::String = "")
    results = OpenCacheLayer.get_content(GOOGLE_SEARCH_ADAPTER(), query)
    formatted = join(["$(i). $(r.title)\n   $(r.url)\n   $(r.content)\n"
                     for (i,r) in enumerate(results)], "\n")
    println("Google Search results:")
    for (i,r) in enumerate(results)
        println("$(i). $(r.title)\n   $(r.url)\n   $(r.content)\n")
    end
    "Search results for '$query':\n\n$formatted"
end
