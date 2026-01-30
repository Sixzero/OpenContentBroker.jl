using ToolCallFormat: @deftool

# Module-level adapters
const WEB_RERANK_GOOGLE_ADAPTER = GoogleAdapter()
const WEB_RERANK_WEB_ADAPTER = DictCacheLayer(FirecrawlAdapter())
const WEB_RERANK_CHUNKER = HtmlChunker()
const WEB_RERANK_PIPELINE = EFFICIENT_PIPELINE()

@deftool "Search and rerank web content with RAG pipeline" function web_search_rerank("Search query" => query::String)
    # Get Google results
    google_results = OpenCacheLayer.get_content(WEB_RERANK_GOOGLE_ADAPTER, query)

    # Scrape and chunk each URL
    contents = String[]
    urls = String[]
    for result in google_results
        content = OpenCacheLayer.get_content(WEB_RERANK_WEB_ADAPTER, result.url)
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
