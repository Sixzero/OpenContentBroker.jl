# Non-HTML response handling for the scraping adapters.
#
# Why: `decode_html` falls back to Latin-1, which *never* fails — so a PDF (or any
# binary) used to be decoded into megabytes of mojibake, `html_to_markdown` then
# threw on the embedded NULs, and the adapter's `"Error: $e"` interpolated the whole
# body back into the result. Here we sniff what actually came back and either
# extract real text (PDF) or refuse, so a binary body can never inflate a tool result.

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
#
# Runs pymupdf in a SUBPROCESS, deliberately not via PythonCall in-process.
# Tools execute inside `@async` tasks on a multithreaded agent (prod runs
# `--threads=8,1`), and an in-process CPython holds the GIL for the whole
# extraction: a Julia thread blocked in C never yields, so it can stall the
# scheduler and wedge unrelated tasks. We hit that class of hang before.
# A subprocess costs ~200ms of interpreter startup (vs ~80ms in-process) —
# irrelevant next to the fetch and the summarizer call — and in exchange the
# work is preemptible, crash-isolated, memory-isolated and timeout-able.

const PDF_EXTRACT_PY = joinpath(@__DIR__, "pdf_extract.py")

# The CondaPkg env owns pymupdf; fall back to whatever `python3` is on PATH.
function _python_exe()
    exe = joinpath(CondaPkg.envdir(), "bin", Sys.iswindows() ? "python.exe" : "python")
    isfile(exe) ? exe : "python3"
end

"""
    pdf_to_text(bytes; max_pages, max_chars, timeout) -> String

Extract the text layer of a PDF. Bounded by page count and characters; anything
dropped is flagged with `…[truncated]` so the summarizer (and the reader) know the
extract is partial. Throws if extraction fails or times out.
"""
function pdf_to_text(bytes::Vector{UInt8}; max_pages::Int = 50, max_chars::Int = 200_000,
                     timeout::Real = 60)
    cmd = `$(_python_exe()) $PDF_EXTRACT_PY $max_pages $max_chars`
    out, err = IOBuffer(), IOBuffer()
    proc = run(pipeline(cmd; stdin = IOBuffer(bytes), stdout = out, stderr = err); wait = false)

    # Kill rather than hang: a malformed PDF must not pin a tool slot forever.
    waiter = @async(wait(proc))
    if timedwait(() -> istaskdone(waiter), float(timeout); pollint = 0.05) === :timed_out
        kill(proc, Base.SIGKILL)
        error("PDF extraction timed out after $(timeout)s")
    end
    success(proc) || error("PDF extraction failed: $(truncate_chars(String(take!(err)), 500))")

    text = truncate_chars(String(take!(out)), max_chars)
    # The child reports "<pages>/<npages>" on stderr so we can flag partial extracts.
    m = match(r"pages=(\d+)/(\d+)", String(take!(err)))
    if m !== nothing
        pages, npages = parse(Int, m[1]), parse(Int, m[2])
        pages < npages && (text *= "\n\n…[truncated: $pages of $npages pages extracted]")
    end
    text
end
