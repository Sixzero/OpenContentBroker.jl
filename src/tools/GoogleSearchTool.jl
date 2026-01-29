# Module-level adapter
const GOOGLE_SEARCH_ADAPTER = GoogleAdapter()

"Search with Google"
@deftool GoogleSearchTool google_search(query::String) = begin
    results = OpenCacheLayer.get_content(GOOGLE_SEARCH_ADAPTER, query)
    formatted = join(["$(i). $(r.title)\n   $(r.url)\n   $(r.content)\n"
                     for (i,r) in enumerate(results)], "\n")
    println("Google Search results:")
    for (i,r) in enumerate(results)
        println("$(i). $(r.title)\n   $(r.url)\n   $(r.content)\n")
    end
    "Search results for '$query':\n\n$formatted"
end
