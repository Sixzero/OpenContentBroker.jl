using HTTP
using JSON3
using URIs
using Dates
using OpenCacheLayer

@kwdef struct GoogleAdapter <: OpenCacheLayer.ChatsLikeAdapter
    api_key::String = get(ENV, "GOOGLE_API_KEY", "")
    cx::String = get(ENV, "GOOGLE_CX", "")  # Custom Search Engine ID
end

function OpenCacheLayer.get_content(adapter::GoogleAdapter, query::String; num::Int=10)
    url = "https://www.googleapis.com/customsearch/v1?" * 
          "key=$(adapter.api_key)&" *
          "cx=$(adapter.cx)&" *
          "q=$(URIs.escapeuri(query))&" *
          "num=$(num)"
    
    response = HTTP.get(url)
    data = JSON3.read(response.body)
    timestamp = now()

    [SearchResult(
        item.title,
        item.link,
        get(item, :snippet, ""),
        1.0 / (i),  # Score based on position
        timestamp
    ) for (i, item) in enumerate(data.items)]
end

OpenCacheLayer.get_adapter_hash(adapter::GoogleAdapter) = 
    "GOOGLE_$(adapter.api_key[1:min(8,length(adapter.api_key))])"
