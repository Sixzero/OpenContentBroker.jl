using ToolCallFormat: @deftool

# Module-level adapters (lazy init for DictCacheLayer to avoid BaseDirs call during precompilation)
const WEB_RERANK_GOOGLE_ADAPTER = GoogleAdapter()
const _WEB_RERANK_WEB_ADAPTER = Ref{Union{DictCacheLayer{FirecrawlAdapter},Nothing}}(nothing)
function get_web_rerank_adapter()
    _WEB_RERANK_WEB_ADAPTER[] === nothing && (_WEB_RERANK_WEB_ADAPTER[] = DictCacheLayer(FirecrawlAdapter()))
    _WEB_RERANK_WEB_ADAPTER[]
end
const WEB_RERANK_CHUNKER = HtmlChunker()
const WEB_RERANK_PIPELINE = EFFICIENT_PIPELINE()

@deftool "Search and rerank web content with RAG pipeline" function web_search_rerank("Search query" => query::String)
    # Get Google results
    google_results = OpenCacheLayer.get_content(WEB_RERANK_GOOGLE_ADAPTER, query)

    # Scrape and chunk each URL
    contents = String[]
    urls = String[]
    for result in google_results
        content = OpenCacheLayer.get_content(get_web_rerank_adapter(), result.url)
        push!(contents, content.content)
        push!(urls, result.url)
    end

    # Get chunks using RAG interface
    all_chunks = RAG.get_chunks(WEB_RERANK_CHUNKER, contents; sources=urls)

    # Search through chunks
    chunk_texts = [get_content(c) for c in all_chunks]
    search_results = search(WEB_RERANK_PIPELINE, chunk_texts, query)

    # Format results
    formatted = join([
        """
        URL: $(get_source(res))
        $(get_content(res))
        """ for res in search_results], "\n\n")

    "Reranked search results for '$query':\n\n$formatted"
end
