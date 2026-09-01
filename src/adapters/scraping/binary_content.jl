# Non-HTML response handling for the scraping adapters.
#
# Why: `decode_html` falls back to Latin-1, which *never* fails — so a PDF (or any
# binary) used to be decoded into megabytes of mojibake, `html_to_markdown` then
# threw on the embedded NULs, and the adapter's `"Error: $e"` interpolated the whole
# body back into the result. Here we sniff what actually came back and either
# extract real text (PDF) or refuse, so a binary body can never inflate a tool result.

using PythonCall

const PDF_MAGIC = b"%PDF-"
const SNIFF_WINDOW = 1_024   # bytes inspected for magic numbers
const BINARY_WINDOW = 8_192  # bytes inspected for NUL (binary tell-tale)
const MAX_ERROR_CHARS = 2_000

# Exact types plus the structured `+json` / `+xml` suffixes. Deliberately not a
# substring match: "x-sh" would then accept application/x-shockwave-flash.
const TEXTUAL_MIMES = Set([
    "application/json", "application/ld+json", "application/xml",
    "application/xhtml+xml", "application/javascript", "application/x-javascript",
    "application/ecmascript", "application/rss+xml", "application/atom+xml",
    "application/yaml", "application/x-yaml", "application/x-sh",
    "application/x-www-form-urlencoded", "application/graphql",
])

_is_textual_mime(mime::AbstractString) =
    startswith(mime, "text/") || mime in TEXTUAL_MIMES ||
    endswith(mime, "+json") || endswith(mime, "+xml")

"""
    bounded_error(msg) -> String

Every error string that can reach a conversation goes through this. Exception
payloads (and user-supplied URLs) can embed a whole response body, which is exactly
how 2.5MB of PDF once escaped into an LLM request.
"""
bounded_error(msg::AbstractString) = truncate_chars(msg, MAX_ERROR_CHARS)

const TRUNCATION_MARK = " …[truncated]"

"""
    truncate_bytes(s, n) -> String

Truncate to at most `n` UTF-8 *bytes* total (marker included), cutting on a char
boundary. `truncate_chars` counts characters, which is 1-4x off in bytes; the
provider limit that killed the original request is a byte limit, so the last cap
before an LLM request must be this one.
"""
function truncate_bytes(s::AbstractString, n::Int)
    sizeof(s) <= n && return String(s)
    keep = max(n - sizeof(TRUNCATION_MARK), 0)
    # Last char boundary ≤ keep bytes: thisind finds the char containing byte
    # keep+1 (it starts at ≤ keep+1); prevind steps to the last char fully inside.
    i = prevind(s, thisind(s, keep + 1))
    String(SubString(s, 1, i)) * TRUNCATION_MARK
end

# Content-Type header value, lowercased, without parameters ("text/html; charset=..." → "text/html").
function _header_mime(headers)
    for (name, value) in headers
        lowercase(String(name)) == "content-type" || continue
        return lowercase(strip(first(split(String(value), ';'))))
    end
    ""
end

"""
    sniff_mime(headers, body) -> String

Best-effort content type, never empty. Magic bytes beat the header (servers
mislabel), a NUL early in the body beats a textual header (binary is binary
whatever the server claims), and the header is the fallback.
"""
function sniff_mime(headers, body::Vector{UInt8})
    # The PDF spec allows leading junk before %PDF-, so search a small window.
    findfirst(PDF_MAGIC, @view(body[1:min(end, SNIFF_WINDOW)])) === nothing ||
        return "application/pdf"
    mime = _header_mime(headers)
    !isempty(mime) && !_is_textual_mime(mime) && return mime
    # Header claims text (or says nothing): believe it only if the bytes look textual.
    UInt8(0) in @view(body[1:min(end, BINARY_WINDOW)]) && return "application/octet-stream"
    isempty(mime) ? "text/html" : mime
end

# --- PDF → text ------------------------------------------------------------

const _pymupdf = Ref{Py}()
function ensure_pymupdf()
    isassigned(_pymupdf) || (_pymupdf[] = pyimport("pymupdf"))
    _pymupdf[]
end

"""
    pdf_to_text(bytes; max_pages, max_chars) -> String

Extract the text layer of a PDF with pymupdf. Bounded by both page count and
characters; anything dropped is flagged with `…[truncated]` so the summarizer (and
the reader) know the extract is partial. Throws if pymupdf is unavailable.
"""
function pdf_to_text(bytes::Vector{UInt8}; max_pages::Int = 50, max_chars::Int = 200_000)
    doc = ensure_pymupdf().open(stream = pybytes(bytes), filetype = "pdf")
    try
        npages = pyconvert(Int, doc.page_count)
        parts, nchars, pages = String[], 0, 0
        for i in 0:min(npages, max_pages)-1
            push!(parts, pyconvert(String, doc[i].get_text()))
            nchars += length(parts[end])
            pages += 1
            nchars > max_chars && break
        end
        text = truncate_chars(join(parts, "\n\n"), max_chars)
        pages < npages && (text *= "\n\n…[truncated: $pages of $npages pages extracted]")
        text
    finally
        doc.close()
    end
end
