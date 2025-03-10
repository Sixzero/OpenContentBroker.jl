using HTTP
using JSON3
using OpenCacheLayer
using OpenCacheLayer: VALID, ASYNC
using Dates


@kwdef struct FirecrawlAdapter <: AbstractUrl2LLMAdapter
    api_key::String=get(ENV, "FIRECRAWL_API_KEY", "")
    formats::Vector{String} = ["markdown"]
    base_url::String = "https://api.firecrawl.dev/v1"
end

struct FirecrawlContent <: AbstractWebContent
    url::String
    content::String
    metadata::Dict{Symbol,Any}
    timestamp::DateTime
end

function OpenCacheLayer.get_content(adapter::FirecrawlAdapter, url::String)
    headers = Dict(
        "Content-Type" => "application/json",
        "Authorization" => "Bearer $(adapter.api_key)"
    )
    
    body = Dict(
        "url" => url,
        "formats" => adapter.formats
    )
    
    try
        response = HTTP.post(
            "$(adapter.base_url)/scrape",
            headers,
            JSON3.write(body)
        )
        
        result = JSON3.read(String(response.body))
        
        FirecrawlContent(
            url,
            result.data.markdown,
            Dict{Symbol,Any}(result.data.metadata),
            now()
        )
    catch e
        @warn "Failed to scrape $url: $e"
        FirecrawlContent(
            url,
            "",  # empty content
            Dict{Symbol,Any}(:error => "Scraping failed: $e"),
            now()
        )
    end
end

OpenCacheLayer.get_timestamp(content::FirecrawlContent) = content.timestamp
OpenCacheLayer.get_adapter_hash(adapter::FirecrawlAdapter) = "FIRECRAWL_" * bytes2hex(sha256(adapter.api_key))

# Cache validity implementation - consider content valid for a week, then async refresh
function OpenCacheLayer.is_cache_valid(content::FirecrawlContent, adapter::FirecrawlAdapter)
    age = now() - content.timestamp
    age <= Hour(24 * 7) ? VALID : ASYNC
end
