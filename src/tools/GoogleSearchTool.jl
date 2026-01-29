using ToolCallFormat: @deftool

# Module-level adapter
const GOOGLE_SEARCH_ADAPTER = GoogleAdapter()

@deftool "Search with Google" function google_search(query::String => "Search query")
    results = OpenCacheLayer.get_content(GOOGLE_SEARCH_ADAPTER, query)
    formatted = join(["$(i). $(r.title)\n   $(r.url)\n   $(r.content)\n"
                     for (i,r) in enumerate(results)], "\n")
    println("Google Search results:")
    for (i,r) in enumerate(results)
        println("$(i). $(r.title)\n   $(r.url)\n   $(r.content)\n")
    end
    "Search results for '$query':\n\n$formatted"
end
