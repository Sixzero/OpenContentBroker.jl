using HTTP
using JSON3
using Dates
using OpenCacheLayer

@kwdef struct TavilyAdapter <: AbstractSearchAdapter
    api_keys::Vector{String} = env_key_pool("TAVILY_API_KEY")
    max_results::Int = 5
end

function OpenCacheLayer.get_content(adapter::TavilyAdapter, query::String; num::Int=adapter.max_results)
    body = JSON3.write(Dict("query" => query, "max_results" => num))
    response = try_keys(adapter.api_keys, "TAVILY_API_KEY") do key
        HTTP.post(
            "https://api.tavily.com/search",
            ["Content-Type" => "application/json",
             "Authorization" => "Bearer $key"],
            body
        )
    end

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

# Key-independent: rotating keys must not invalidate the cache.
OpenCacheLayer.get_adapter_hash(adapter::TavilyAdapter) = "TAVILY"
