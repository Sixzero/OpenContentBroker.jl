using HTTP
using Dates
using OpenCacheLayer
using JSON3
using SHA

@enum CachePolicy begin
    RESPECT      # Respect HTTP cache headers
    ALWAYS_STALE # Always fetch fresh content
    ALWAYS_VALID # Always use cached content
end

struct WebContent <: AbstractWebContent
    url::String
    content::String
    raw_content::Vector{UInt8}
    etag::Union{String,Nothing}
    last_modified::Union{DateTime,Nothing}
    cache_control::Union{String,Nothing}
    timestamp::DateTime
end

@kwdef struct RawWebAdapter <: AbstractUrl2LLMAdapter
    headers::Dict{String,String}=Dict{String,String}()
    cache_policy::CachePolicy=RESPECT
end

# Interface implementations
function OpenCacheLayer.is_cache_valid(content::WebContent, adapter::RawWebAdapter)
    adapter.cache_policy === ALWAYS_STALE && return STALE
    adapter.cache_policy === ALWAYS_VALID && return VALID
    
    isnothing(content.cache_control) && return ASYNC
    
    if contains(content.cache_control, "max-age=")
        max_age = parse(Int, match(r"max-age=(\d+)", content.cache_control).captures[1])
        age = now() - content.timestamp
        
        if age <= Second(max_age)
            return VALID
        elseif age <= Second(max_age * 10)  # Allow async refresh within double max-age
            return ASYNC
        end
    end
    ASYNC
end

function OpenCacheLayer.get_content(adapter::RawWebAdapter, url::String)
    response = HTTP.get(url, adapter.headers)
    headers = Dict(response.headers)
    
    WebContent(
        url,
        String(response.body),
        response.body,
        get(headers, "ETag", nothing),
        haskey(headers, "Last-Modified") ? try_parse_http_date(String(headers["Last-Modified"])) : nothing,
        get(headers, "Cache-Control", nothing),
        now()
    )
end

function OpenCacheLayer.get_adapter_hash(adapter::RawWebAdapter)
    # For WebAdapter, we use headers as part of the hash since they can affect responses
    # If no special headers, just return basic identifier
    isempty(adapter.headers) ? "WEB_ADAPTER" : bytes2hex(sha256(JSON3.write(adapter.headers)))
end

OpenCacheLayer.get_timestamp(content::WebContent) = content.timestamp

# Helper function to parse HTTP date formats
function try_parse_http_date(date_str::String)
    try
        DateTime(date_str, "e, d u Y H:M:S GMT")
    catch
        nothing
    end
end
