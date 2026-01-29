# Module-level adapter
const GOOGLE_RAG_ADAPTER = GoogleRAGAdapter()

"Search with Google and rerank results with RAG pipeline for higher quality results"
@deftool GoogleRAGTool google_rag(query::String) = begin
    response = OpenCacheLayer.get_content(GOOGLE_RAG_ADAPTER, query)
    results, elapsed, cost = response.results, response.elapsed, response.cost

    result = join([
        """
        # URL: $(string(r.url))
        $(r.content)
        """ for r in results], "\n\n")

    println("Google RAG Search results:")
    println(join(["URL: $(string(r.url))" for r in results], "\n"))
    if cost > 0
        println("Cost: \$$(round(cost, digits=4))")
    end

    "Google RAG Search results for '$query':\n$result"
end
