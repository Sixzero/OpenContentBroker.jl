using OpenCacheLayer
using EasyContext: search, AbstractRAGPipeline
using RAGTools: AbstractChunker

@kwdef struct GoogleRAGResult
    url::String
    content::String
    score::Float64=0.0
end

# Singleton pattern for global web cache
const _GLOBAL_WEB_CACHE = Ref{Union{DictCacheLayer{<:AbstractUrl2LLMAdapter},Nothing}}(nothing)
function get_global_web_cache()
    if _GLOBAL_WEB_CACHE[] === nothing
        _GLOBAL_WEB_CACHE[] = DictCacheLayer(MarkdownifyAdapter())
    end
    _GLOBAL_WEB_CACHE[]
end

@kwdef struct GoogleRAGAdapter <: StatusBasedAdapter
    google_adapter::AbstractSearchAdapter = FallbackSearchAdapter()
    chunker::HtmlChunker = HtmlChunker()
    rag_pipeline::AbstractRAGPipeline = EFFICIENT_PIPELINE(; model="gemfl")
    max_results::Int = 10
    firecrawl_cost_per_request::Float64 = 20.0 / 3000.0
end

# Helper function to check if URL should be skipped
function should_skip_url(url::String)
    lowercase_url = lowercase(url)
    return endswith(lowercase_url, ".pdf")
end

function OpenCacheLayer.get_content(adapter::GoogleRAGAdapter, query::String)
    start_time = time()

    google_results = OpenCacheLayer.get_content(adapter.google_adapter, query; num=adapter.max_results)
    
    # Filter out PDF URLs
    filtered_results = filter(result -> !should_skip_url(result.url), google_results)
    skipped_count = length(google_results) - length(filtered_results)
    
    if skipped_count > 0
        println("⚠️  Skipped $skipped_count PDF URLs")
    end
    
    println("📑 Found $(length(filtered_results)) valid search results")
    
    if isempty(filtered_results)
        println("❌ No valid results found after filtering")
        return (results=GoogleRAGResult[], elapsed=time() - start_time, cost=0.0)
    end
    
    # Track Firecrawl requests for cost calculation
    firecrawl_requests = 0
    
    # Get global web cache
    web_cache = get_global_web_cache()
    
    # Scrape and chunk each URL using asyncmap
    all_chunks_raw = asyncmap(filtered_results) do result
        println("🌐 Scraping: $(result.url)")
        content = OpenCacheLayer.get_content(web_cache, result.url)
        firecrawl_requests += 1  # Count each request
        chunks = RAG.get_chunks(adapter.chunker, content.content; source=content.url)
        println("✂️  Chunked $(length(chunks)) parts from: $(result.url)")
        chunks
    end
    all_chunks = vcat(all_chunks_raw...)
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
    "GOOGLE_RAG_" * get_adapter_hash(adapter.google_adapter)
