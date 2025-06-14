using OpenCacheLayer
using EasyContext: search, AbstractRAGPipeline
using RAGTools: AbstractChunker

@kwdef struct GoogleRAGResult
    url::String
    content::String
    score::Float64=0.0
end

@kwdef struct GoogleRAGAdapter <: StatusBasedAdapter
    google_adapter::GoogleAdapter = GoogleAdapter()
    web_adapter::DictCacheLayer{<:AbstractUrl2LLMAdapter} = DictCacheLayer(FirecrawlAdapter())
    chunker::HtmlChunker = HtmlChunker()
    rag_pipeline::AbstractRAGPipeline = EFFICIENT_PIPELINE()
    max_results::Int = 10
    firecrawl_cost_per_request::Float64 = 20.0 / 3000.0  # $20 for 3000 requests = ~$0.0067 per request
end

function OpenCacheLayer.get_content(adapter::GoogleRAGAdapter, query::String)
    start_time = time()

    # Get top Google results
    google_results = OpenCacheLayer.get_content(adapter.google_adapter, query; num=adapter.max_results)
    println("📑 Found $(length(google_results)) Google results")
    
    # Track Firecrawl requests for cost calculation
    firecrawl_requests = 0
    
    # Scrape and chunk each URL using asyncmap
    all_chunks = vcat(asyncmap(google_results) do result
        println("🌐 Scraping: $(result.url)")
        content = OpenCacheLayer.get_content(adapter.web_adapter, result.url)
        firecrawl_requests += 1  # Count each request
        chunks = RAG.get_chunks(adapter.chunker, content.content; source=result.url)
        println("✂️  Chunked $(length(chunks)) parts from: $(result.url)")
        chunks
    end...)
    
    println("🔄 Processing $(length(all_chunks)) total chunks through RAG pipeline")
    chunk_texts = string.(all_chunks)
    search_results = search(adapter.rag_pipeline, chunk_texts, query)
    selected_chunks = all_chunks[findall(in(search_results), chunk_texts)]
    
    elapsed = time() - start_time
    cost = firecrawl_requests * adapter.firecrawl_cost_per_request
    
    println("✅ Selected $(length(selected_chunks)) relevant chunks")
    println("💰 Cost: \$$(round(cost, digits=4)) ($(firecrawl_requests) Firecrawl requests)")
    println("⏱️  Elapsed: $(round(elapsed, digits=2))s")
    
    results = [GoogleRAGResult(
        url=chunk.source,
        content=string(chunk),
    ) for chunk in selected_chunks]
    
    return (results=results, elapsed=elapsed, cost=cost)
end

OpenCacheLayer.get_adapter_hash(adapter::GoogleRAGAdapter) = 
    "GOOGLE_RAG_" * get_adapter_hash(adapter.google_adapter) * "_" * get_adapter_hash(adapter.web_adapter)
