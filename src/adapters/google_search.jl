using HTTP
using JSON3
using URIs
using Dates
using OpenCacheLayer

@kwdef struct GoogleAdapter <: AbstractSearchAdapter
    api_keys::Vector{String} = env_key_pool("GOOGLE_API_KEY")
    cx::String = get(ENV, "GOOGLE_CX", "")  # Custom Search Engine ID
end

function OpenCacheLayer.get_content(adapter::GoogleAdapter, query::String; num::Int=10)
    response = try_keys(adapter.api_keys, "GOOGLE_API_KEY") do key
        HTTP.get("https://www.googleapis.com/customsearch/v1?" *
                 "key=$(key)&" *
                 "cx=$(adapter.cx)&" *
                 "q=$(URIs.escapeuri(query))&" *
                 "num=$(num)")
    end
    data = JSON3.read(response.body)
    
    # Debug message to understand what's in the response
    if !haskey(data, :items)
        println("🐛 DEBUG: Google API response missing 'items' field. Available keys: $(keys(data))")
        println("🐛 DEBUG: Full response: $(data)")
        return SearchResult[]
    end
    
    timestamp = now()

    [SearchResult(
        item.title,
        item.link,
        get(item, :snippet, ""),
        1.0 / (i),  # Score based on position
        timestamp
    ) for (i, item) in enumerate(data.items)]
end

# Key-independent: rotating keys must not invalidate the cache.
OpenCacheLayer.get_adapter_hash(adapter::GoogleAdapter) = "GOOGLE_$(adapter.cx)"
