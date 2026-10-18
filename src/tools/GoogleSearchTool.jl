using ToolCallFormat: @deftool

# Lazy-initialized adapter (reads ENV at first use, not precompile time)
# Serper (Google SERP); keys rotate + retry in try_keys.
const _google_search_adapter_ref = Ref{Union{Nothing,AbstractSearchAdapter}}(nothing)
function GOOGLE_SEARCH_ADAPTER()
    if _google_search_adapter_ref[] === nothing
        _google_search_adapter_ref[] = SerpAdapter(engine="google")
    end
    _google_search_adapter_ref[]
end

format_search_results(query, results) =
    "Search results for '$query':\n\n" *
    join(["$(i). $(r.title)\n   $(r.url)\n   $(r.content)" for (i,r) in enumerate(results)], "\n\n")

@deftool "Search with Google. Returns titles, URLs and snippets only; call webfetch on the relevant URLs when snippets are not enough." function google_search("Search query" => query::String)
    format_search_results(query, OpenCacheLayer.get_content(GOOGLE_SEARCH_ADAPTER(), query))
end
