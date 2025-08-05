using OpenContentBroker
using OpenCacheLayer
using Dates

function scrape_and_show(initial_url, topic; strategy=AIRelevanceStrategy())
    # Create adapter with specified strategy
    adapter = WebScraperAdapter(
        headers=Dict(
            "User-Agent" => "OpenContentBroker.jl/0.1.0",
            "Accept" => "text/html"
        ),
        max_depth=2,
        max_urls=3,
        relevance_strategy=strategy,
        
    )
    
    # Wrap with cache layer
    cached_adapter = DictCacheLayer(adapter)
    
    println("\nInitiating scrape of: ", initial_url)
    println("Topic: ", topic)
    println("Using strategy: ", typeof(strategy))
    
    content = get_content(cached_adapter, topic, extra_urls=[initial_url])
    
    println("\nSummary of main page:")
    println("-" ^ 50)
    println(content.summary)
    println("-" ^ 50)
    
    println("\nRelated URLs found and scraped: ", length(content.related_urls))
    for (url, content) in content.related_urls
        println("\nURL: ", url)
        println("Content length: ", length(content), " bytes")
        println("-" ^ 30)
    end
end

# Test with both strategies
url = "https://julialang.org"
topic = "Julia programming language performance and features"

println("Testing with AI Relevance Strategy:")
@time scrape_and_show(url, topic)

# println("\nTesting with Keyword Relevance Strategy:")
# @time scrape_and_show(url, topic, strategy=KeywordRelevanceStrategy())
