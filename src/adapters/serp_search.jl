using HTTP
using JSON3
using Dates
using OpenCacheLayer

@kwdef struct SerpAdapter <: AbstractSearchAdapter
    api_keys::Vector{String} = env_key_pool("SERP_API_KEY")
    engine::String = "google"  # Can be: google, bing, baidu, yandex, yahoo
end

function OpenCacheLayer.get_content(adapter::SerpAdapter, query::String; num::Int=10)
    body = JSON3.write(Dict("q" => query, "num" => num))
    response = try_keys(adapter.api_keys, "SERP_API_KEY") do key
        HTTP.post(
            "https://google.serper.dev/search?engine=$(adapter.engine)",
            ["X-API-KEY" => key, "Content-Type" => "application/json"],
            body
        )
    end

    data = JSON3.read(response.body)
    results = SearchResult[]
    timestamp = now()  # Single timestamp for all results

    # Process organic results
    for result in data.organic
        push!(results, SearchResult(
            get(result, :title, ""),
            result.link,
            get(result, :snippet, ""),
            1 / get(result, :position, 1.0),
            timestamp
        ))
    end

    results
end

# Key-independent: rotating keys must not invalidate the cache.
OpenCacheLayer.get_adapter_hash(adapter::SerpAdapter) = "SERP_$(adapter.engine)"
