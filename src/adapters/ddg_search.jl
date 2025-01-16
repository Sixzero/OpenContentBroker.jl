using HTTP
using JSON3
using URIs
using Dates
using OpenCacheLayer

@kwdef struct DDGAdapter <: OpenCacheLayer.ChatsLikeAdapter
    region::String = "wt-wt"  # worldwide
end

function OpenCacheLayer.get_content(adapter::DDGAdapter, query::String)
    # Using the HTML search endpoint with HTML output
    response = HTTP.get(
        "https://html.duckduckgo.com/html/?q=$(URIs.escapeuri(query))",
        headers=Dict("User-Agent" => "Mozilla/5.0")
    )
    
    html_content = String(response.body)
    
    # Basic parsing of results using regex
    results = SearchResult[]
    timestamp = now()
    
    # Extract result blocks
    result_blocks = eachmatch(r"<div class=\"result[^>]*>.*?<a[^>]*href=\"([^\"]+)\"[^>]*>.*?<h2[^>]*>(.*?)</h2>.*?<a[^>]*class=\"result__snippet\"[^>]*>(.*?)</a>"s, html_content)
    
    for (i, match) in enumerate(result_blocks)
        # Extract and clean the URL from DuckDuckGo's redirect
        raw_url = match[1]
        url = if occursin("uddg=", raw_url)
            decoded_url = URIs.unescapeuri(split(split(raw_url, "uddg=")[2], "&")[1])
            startswith(decoded_url, "//") ? "https:" * decoded_url : decoded_url
        else
            startswith(raw_url, "//") ? "https:" * raw_url : raw_url
        end
        
        title = strip(replace(match[2], r"<[^>]+>" => ""))  # Remove HTML tags
        snippet = strip(replace(match[3], r"<[^>]+>" => "")) # Remove HTML tags
        
        push!(results, SearchResult(
            title,
            url,
            snippet,
            1.0 / i,  # Score decreases with position
            timestamp
        ))
    end
    
    results
end

OpenCacheLayer.get_adapter_hash(::DDGAdapter) = "DDG_SEARCH"

function OpenCacheLayer.is_cache_valid(results::Vector{SearchResult}, ::DDGAdapter)
    isempty(results) && return false
    # Consider results valid for 1 day
    now() - results[1].timestamp < Day(1)
end
