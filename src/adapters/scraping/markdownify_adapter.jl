using HTTP
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

# Truncate a string to at most `n` chars on a char boundary, marking elision.
truncate_chars(s::AbstractString, n::Int) =
    length(s) <= n ? s : String(first(s, n)) * " …[truncated]"

# Recover readable content from client-rendered (SPA) pages whose <body> is empty.
# Pulls what IS present in the raw HTML: <title>, meta description/keywords/OG tags,
# and any JSON-LD blocks — enough for the summarizer to work with.
# All sizes are bounded so a huge JSON-LD catalog can't blow up the LLM prompt.
function extract_static_content(html::AbstractString;
        max_meta::Int = 2_000,      # per meta value
        max_ld_block::Int = 8_000,  # per JSON-LD block
        max_ld_blocks::Int = 3,     # number of JSON-LD blocks
        max_total::Int = 20_000,    # whole recovered output
    )
    parts = String[]

    m = match(r"<title[^>]*>(.*?)</title>"is, html)
    m !== nothing && push!(parts, "# " * truncate_chars(strip(m.captures[1]), max_meta))

    for mt in eachmatch(r"<meta[^>]+>"i, html)
        tag = mt.match
        name_m = match(r"(?:name|property)=[\"']([^\"']+)[\"']"i, tag)
        cont_m = match(r"content=[\"']([^\"']*)[\"']"i, tag)
        (name_m === nothing || cont_m === nothing) && continue
        name = lowercase(name_m.captures[1])
        content = strip(cont_m.captures[1])
        isempty(content) && continue
        if name in ("description", "keywords", "og:title", "og:description", "twitter:title", "twitter:description")
            push!(parts, "$name: $(truncate_chars(content, max_meta))")
        end
    end

    ld_count = 0
    for mj in eachmatch(r"<script[^>]+type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"is, html)
        ld_count += 1
        ld_count > max_ld_blocks && break
        push!(parts, "```json\n" * truncate_chars(strip(mj.captures[1]), max_ld_block) * "\n```")
    end

    truncate_chars(join(unique(parts), "\n\n"), max_total)
end

@kwdef struct MarkdownifyAdapter <: AbstractUrl2LLMAdapter
    headers::Dict{String,String} = Dict("User-Agent" => "Mozilla/5.0 (compatible; MarkdownifyBot)")
    cache_policy::CachePolicy = RESPECT
    timeout::Int = 30
    # Cap chars sent to the summarizer LLM. Haiku 4.5 has a ~200K-token window
    # (~600-800KB), so this is generous — it only guards against runaway pages,
    # not normal ones. ~500KB ≈ 125K tokens, leaving headroom for prompt + output.
    max_content::Int = 500_000
end

struct MarkdownifyContent <: AbstractWebContent
    url::String
    content::String
    metadata::Dict{Symbol,Any}
    timestamp::DateTime
end


# Single funnel for every failure result, so no error path can leak an unbounded
# payload (exception text, huge URL) into the conversation.
_error_content(url::AbstractString, mime::AbstractString, code::String, msg::AbstractString) =
    MarkdownifyContent(truncate_chars(url, 500), bounded_error(msg),
        Dict{Symbol,Any}(:error => code, :mime => mime), now())

function OpenCacheLayer.get_content(adapter::MarkdownifyAdapter, url::String)
    try
        # Fetch using HTTP.jl with timeout (retry=true is default; bump retries for transient task failures)
        response = HTTP.get(url;
            headers=collect(adapter.headers),
            readtimeout=adapter.timeout,
            retries=2,
        )
        
        response.status != 200 && return MarkdownifyContent(
            url, "HTTP $(response.status)",
            Dict{Symbol,Any}(:error => "HTTP $(response.status)"), now()
        )

        # Non-HTML bodies must never reach decode_html: its Latin-1 fallback never
        # fails, so a PDF/binary would turn into megabytes of mojibake.
        mime = sniff_mime(response.headers, response.body)
        if mime == "application/pdf"
            text = try
                pdf_to_text(response.body; max_chars = adapter.max_content)
            catch e
                return _error_content(url, mime, "pdf_extract",
                    "Failed to extract text from PDF: $(sprint(showerror, e))")
            end
            isempty(strip(text)) && return _error_content(url, mime, "pdf_no_text",
                "PDF has no extractable text layer (likely a scanned document).")
            return MarkdownifyContent(url, text, Dict{Symbol,Any}(:mime => mime), now())
        elseif !_is_textual_mime(mime)
            return _error_content(url, mime, "unsupported_content_type",
                "Unsupported content type '$mime' (binary content is not fetched).")
        end

        html_content = decode_html(response.body, response.headers)

        # Convert to markdown (pure Julia, Gumbo-based — see html_to_markdown.jl)
        markdown_content = html_to_markdown(html_content)

        # SPA fallback: client-rendered pages (Next.js/React) have an empty <body>;
        # markdownify strips the <script> payload, leaving nothing. Recover the content
        # that IS present in the raw HTML (meta tags, JSON-LD, __NEXT_DATA__).
        if length(strip(markdown_content)) < 200
            recovered = extract_static_content(html_content)
            isempty(strip(recovered)) || (markdown_content = recovered)
        end

        # Bound the payload sent to the summarizer LLM (guards against huge pages).
        markdown_content = truncate_chars(markdown_content, adapter.max_content)

        MarkdownifyContent(url, markdown_content, Dict{Symbol,Any}(), now())
        
    catch e
        # Bound the message: exception payloads can embed the whole response body —
        # that is exactly how 2.5MB of PDF once reached an LLM request.
        _error_content(url, "", "fetch_failed", "Error: $(sprint(showerror, e))")
    end
end

OpenCacheLayer.is_cache_valid(content::MarkdownifyContent, adapter::MarkdownifyAdapter) = 
    adapter.cache_policy === ALWAYS_STALE ? STALE : 
    adapter.cache_policy === ALWAYS_VALID ? VALID : ASYNC

OpenCacheLayer.get_timestamp(content::MarkdownifyContent) = content.timestamp

# _JL: pure-Julia converter output differs from the old python-markdownify.
# _V2: content-type sniffing + PDF extraction — must not serve pre-fix cached
# entries, which can still hold megabytes of binary mojibake.
OpenCacheLayer.get_adapter_hash(adapter::MarkdownifyAdapter) = "MARKDOWNIFY_JL_V2"