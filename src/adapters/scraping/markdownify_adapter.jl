using HTTP
using PyCall
using OpenCacheLayer
using OpenCacheLayer: VALID, ASYNC, STALE
using Dates

@kwdef struct MarkdownifyAdapter <: AbstractUrl2LLMAdapter
    headers::Dict{String,String} = Dict("User-Agent" => "Mozilla/5.0 (compatible; MarkdownifyBot)")
    cache_policy::CachePolicy = RESPECT
    timeout::Int = 30
end

struct MarkdownifyContent <: AbstractWebContent
    url::String
    content::String
    metadata::Dict{Symbol,Any}
    timestamp::DateTime
end

# Initialize markdownify lazily
const markdownify = PyNULL()

function get_markdownify()
    if markdownify == PyNULL()
        try
            # TODO probably even better solutiion than markdownify: https://github.com/Goldziher/html-to-markdown
            copy!(markdownify, pyimport("markdownify"))
        catch e
            error("Failed to import markdownify. Install with: python3 -m pip install markdownify")
        end
    end
    markdownify
end

function OpenCacheLayer.get_content(adapter::MarkdownifyAdapter, url::String)
    try
        # Fetch using HTTP.jl with timeout
        response = HTTP.get(url; 
            headers=collect(adapter.headers),
            readtimeout=adapter.timeout
        )
        
        response.status != 200 && return MarkdownifyContent(
            url, "HTTP $(response.status)", 
            Dict{Symbol,Any}(:error => "HTTP $(response.status)"), now()
        )
        
        html_content = String(response.body)
        
        # Convert to markdown using PyCall
        markdown_content = get_markdownify().markdownify(html_content; heading_style="ATX")
        
        MarkdownifyContent(url, markdown_content, Dict{Symbol,Any}(), now())
        
    catch e
        MarkdownifyContent(url, "Error: $e", Dict{Symbol,Any}(:error => string(e)), now())
    end
end

OpenCacheLayer.is_cache_valid(content::MarkdownifyContent, adapter::MarkdownifyAdapter) = 
    adapter.cache_policy === ALWAYS_STALE ? STALE : 
    adapter.cache_policy === ALWAYS_VALID ? VALID : ASYNC

OpenCacheLayer.get_timestamp(content::MarkdownifyContent) = content.timestamp

OpenCacheLayer.get_adapter_hash(adapter::MarkdownifyAdapter) = "MARKDOWNIFY"