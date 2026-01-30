using HTTP
using PythonCall
using OpenCacheLayer
using OpenCacheLayer: VALID, ASYNC, STALE
using Dates

# Convert Latin-1 bytes to UTF-8 string (each byte maps to Unicode codepoint)
function latin1_to_utf8(bytes::Vector{UInt8})
    io = IOBuffer()
    for b in bytes
        print(io, Char(b))
    end
    String(take!(io))
end

# Extract charset from Content-Type header or HTML meta tag
function detect_charset(headers, body::Vector{UInt8})
    # Check Content-Type header first
    for (name, value) in headers
        if lowercase(String(name)) == "content-type"
            m = match(r"charset=([^\s;]+)"i, String(value))
            m !== nothing && return lowercase(m.captures[1])
        end
    end
    # Check HTML meta tag (only first 1024 bytes, using Latin-1 to avoid errors)
    head = latin1_to_utf8(body[1:min(1024, length(body))])
    m = match(r"<meta[^>]+charset=[\"']?([^\"'\s>]+)"i, head)
    m !== nothing && return lowercase(m.captures[1])
    m = match(r"<meta[^>]+content=[\"'][^\"']*charset=([^\"'\s;]+)"i, head)
    m !== nothing && return lowercase(m.captures[1])
    return nothing
end

# Decode bytes to string with charset detection and fallback
function decode_html(body::Vector{UInt8}, headers)
    charset = detect_charset(headers, body)
    # Try detected charset or UTF-8 first
    if charset in ("utf-8", "utf8", nothing)
        s = String(copy(body))
        isvalid(s) && return s
        # Invalid UTF-8, fall through to Latin-1
    end
    # For ISO-8859-1, Windows-1252, or as fallback (Latin-1 never fails)
    return latin1_to_utf8(body)
end

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
const _markdownify_module = Ref{Py}()

function get_markdownify()
    if !isassigned(_markdownify_module)
        try
            # TODO probably even better solution than markdownify: https://github.com/Goldziher/html-to-markdown
            _markdownify_module[] = pyimport("markdownify")
        catch e
            error("Failed to import markdownify. Install with: python3 -m pip install markdownify")
        end
    end
    _markdownify_module[]
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

        html_content = decode_html(response.body, response.headers)
        
        # Convert to markdown using PythonCall
        markdown_content = pyconvert(String, get_markdownify().markdownify(html_content; heading_style="ATX"))
        
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