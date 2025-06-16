using HTTP
using JSON3
using Dates
using OpenCacheLayer

@kwdef struct TavilyAdapter <: AbstractSearchAdapter
    api_key::String = get(ENV, "TAVILY_API_KEY", "")
    max_results::Int = 5
end

function OpenCacheLayer.get_content(adapter::TavilyAdapter, query::String)
    response = HTTP.post(
        "https://api.tavily.com/search",
        ["Content-Type" => "application/json",
         "Authorization" => "Bearer $(adapter.api_key)"],
        JSON3.write(Dict(
            "query" => query,
            "max_results" => adapter.max_results
        ))
    )
    
    data = JSON3.read(response.body)
    timestamp = now()  # Single timestamp for all results
    
    [SearchResult(
        result.title,
        result.url,
        result.content,
        result.score,
        timestamp
    ) for result in data.results]
end

OpenCacheLayer.get_adapter_hash(adapter::TavilyAdapter) = 
    "TAVILY_$(adapter.api_key[1:min(8,length(adapter.api_key))])"
