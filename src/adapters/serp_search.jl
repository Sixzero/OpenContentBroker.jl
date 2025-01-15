using HTTP
using JSON3
using Dates
using OpenCacheLayer

struct SerpAdapter <: OpenCacheLayer.ChatsLikeAdapter
    api_key::String
end

function OpenCacheLayer.get_content(adapter::SerpAdapter, query::String)
    response = HTTP.post(
        "https://google.serper.dev/search",
        ["X-API-KEY" => adapter.api_key,
         "Content-Type" => "application/json"],
        JSON3.write(Dict("q" => query))
    )
    
    data = JSON3.read(response.body)
    results = SearchResult[]
    
    # Process organic results
    for result in data.organic
        push!(results, SearchResult(
            result.title,
            result.link,
            result.snippet,
            get(result, :position, 1.0) / 10,  # Convert position to score
            now()
        ))
    end
    
    results
end

OpenCacheLayer.get_adapter_hash(adapter::SerpAdapter) = 
    "SERP_$(adapter.api_key[1:min(8,length(adapter.api_key))])"
