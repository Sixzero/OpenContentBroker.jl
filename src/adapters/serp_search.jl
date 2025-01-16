using HTTP
using JSON3
using Dates
using OpenCacheLayer

@kwdef struct SerpAdapter <: OpenCacheLayer.ChatsLikeAdapter
    api_key::String = get(ENV, "SERP_API_KEY", "")
    engine::String = "google"  # Can be: google, bing, baidu, yandex, yahoo
end

function OpenCacheLayer.get_content(adapter::SerpAdapter, query::String)
    response = HTTP.post(
        "https://google.serper.dev/search?engine=$(adapter.engine)",
        ["X-API-KEY" => adapter.api_key,
         "Content-Type" => "application/json"],
        JSON3.write(Dict("q" => query))
    )
    
    data = JSON3.read(response.body)
    results = SearchResult[]
    timestamp = now()  # Single timestamp for all results
    
    # Process organic results
    for result in data.organic
        push!(results, SearchResult(
            result.title,
            result.link,
            result.snippet,
            1 / get(result, :position, 1.0),
            timestamp
        ))
    end
    
    results
end

OpenCacheLayer.get_adapter_hash(adapter::SerpAdapter) = 
    "SERP_$(adapter.engine)_$(adapter.api_key[1:min(8,length(adapter.api_key))])"
