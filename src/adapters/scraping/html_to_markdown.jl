# Pure-Julia HTML → Markdown conversion (replaces the pyimport("markdownify") dependency).
#
# Mirrors python-markdownify's ATX output for the constructs that matter to a
# summarizer LLM: headings, paragraphs, lists, links, images, bold/italic/code,
# pre blocks, blockquotes, tables, hr. Script/style/head content is dropped.

using Gumbo

const _MD_SKIP_TAGS = Set([:script, :style, :head, :noscript, :template, :iframe, :svg, :canvas])
const _MD_INLINE_TAGS = Set([:a, :b, :strong, :i, :em, :code, :span, :img, :br, :sub, :sup, :u, :s, :small, :abbr, :mark, :time, :label])

html_to_markdown(html::AbstractString) = begin
    doc = Gumbo.parsehtml(String(html))
    io = IOBuffer()
    # <head> is skipped wholesale below; surface its <title> like markdownify does.
    m = match(r"<title[^>]*>(.*?)</title>"is, html)
    m !== nothing && !isempty(strip(m.captures[1])) && print(io, strip(m.captures[1]), "\n\n")
    _md_children(io, doc.root, _MDCtx())
    _md_clean(String(take!(io)))
end

# Rendering context: list nesting + <pre> literal mode.
Base.@kwdef mutable struct _MDCtx
    list_stack::Vector{Symbol} = Symbol[]   # :ul / :ol nesting
    ol_counters::Vector{Int} = Int[]
    pre::Bool = false
end

# Collapse runs of whitespace like HTML rendering does (outside <pre>).
_md_text(t::AbstractString, pre::Bool) = pre ? t : replace(t, r"\s+" => " ")

# Final cleanup: ≥3 newlines → 2, trim outer blank space.
_md_clean(s::AbstractString) = strip(replace(s, r"\n{3,}" => "\n\n"))

_md_children(io::IO, el::HTMLElement, ctx::_MDCtx) =
    for c in el.children
        _md_node(io, c, ctx)
    end

# Render children into a string (for constructs that need their inner text first).
function _md_inner(el::HTMLElement, ctx::_MDCtx)
    buf = IOBuffer()
    _md_children(buf, el, ctx)
    String(take!(buf))
end

_md_node(io::IO, t::HTMLText, ctx::_MDCtx) = print(io, _md_text(t.text, ctx.pre))

function _md_node(io::IO, el::HTMLElement{T}, ctx::_MDCtx) where T
    T in _MD_SKIP_TAGS && return

    if T in (:h1, :h2, :h3, :h4, :h5, :h6)
        level = parse(Int, string(T)[2])
        print(io, "\n\n", "#"^level, " ", strip(_md_inner(el, ctx)), "\n\n")
    elseif T === :p || T === :div || T === :section || T === :article || T === :main ||
           T === :header || T === :footer || T === :figure || T === :figcaption ||
           T === :form || T === :fieldset || T === :details || T === :summary || T === :center
        # Block containers: surround with blank lines only when they hold block content;
        # markdownify keeps inline-only divs on one line too, but a paragraph break is safe.
        print(io, "\n\n")
        _md_children(io, el, ctx)
        print(io, "\n\n")
    elseif T === :br
        print(io, "\n")
    elseif T === :hr
        print(io, "\n\n---\n\n")
    elseif T === :a
        href = getattr(el, "href", "")
        text = strip(_md_inner(el, ctx))
        isempty(text) && (text = href)
        if isempty(href) || startswith(href, "javascript:")
            print(io, text)
        elseif text == href
            print(io, "<", href, ">")
        else
            print(io, "[", text, "](", href, ")")
        end
    elseif T === :img
        alt = getattr(el, "alt", "")
        src = getattr(el, "src", "")
        isempty(src) || print(io, "![", alt, "](", src, ")")
    elseif T === :strong || T === :b
        inner = strip(_md_inner(el, ctx))
        isempty(inner) || print(io, "**", inner, "**")
    elseif T === :em || T === :i
        inner = strip(_md_inner(el, ctx))
        isempty(inner) || print(io, "*", inner, "*")
    elseif T === :code
        if ctx.pre  # inside <pre><code> — literal
            _md_children(io, el, ctx)
        else
            inner = strip(_md_inner(el, ctx))
            isempty(inner) || print(io, "`", inner, "`")
        end
    elseif T === :pre
        was = ctx.pre; ctx.pre = true
        inner = _md_inner(el, ctx)
        ctx.pre = was
        print(io, "\n\n```\n", strip(inner, '\n'), "\n```\n\n")
    elseif T === :blockquote
        inner = _md_clean(_md_inner(el, ctx))
        quoted = join(("> " * line for line in split(inner, '\n')), "\n")
        print(io, "\n\n", quoted, "\n\n")
    elseif T === :ul || T === :ol
        push!(ctx.list_stack, T)
        T === :ol && push!(ctx.ol_counters, 0)
        print(io, "\n")
        _md_children(io, el, ctx)
        T === :ol && pop!(ctx.ol_counters)
        pop!(ctx.list_stack)
        isempty(ctx.list_stack) && print(io, "\n")
    elseif T === :li
        depth = max(length(ctx.list_stack) - 1, 0)
        indent = "  "^depth
        marker = if !isempty(ctx.list_stack) && ctx.list_stack[end] === :ol
            ctx.ol_counters[end] += 1
            "$(ctx.ol_counters[end])."
        else
            "-"
        end
        inner = strip(_md_clean(_md_inner(el, ctx)))
        # Multi-line items: continuation lines aligned under the text.
        cont = indent * " "^(length(marker) + 1)
        inner = replace(inner, "\n" => "\n" * cont)
        print(io, indent, marker, " ", inner, "\n")
    elseif T === :table
        _md_table(io, el, ctx)
    elseif T === :tr || T === :td || T === :th || T === :thead || T === :tbody || T === :tfoot
        # Reached only for malformed tables outside <table>; just recurse.
        _md_children(io, el, ctx)
        print(io, " ")
    else
        # Unknown/other tags (span, nav, aside, …): recurse transparently.
        _md_children(io, el, ctx)
    end
end

# ---- tables ----

_md_rows(el::HTMLElement) = begin
    rows = HTMLElement[]
    for c in el.children
        c isa HTMLElement || continue
        tagname = Gumbo.tag(c)
        if tagname === :tr
            push!(rows, c)
        elseif tagname in (:thead, :tbody, :tfoot)
            append!(rows, _md_rows(c))
        end
    end
    rows
end

_md_has_th(rows) = any(any(c isa HTMLElement && Gumbo.tag(c) === :th for c in r.children) for r in rows)

function _md_table(io::IO, el::HTMLElement, ctx::_MDCtx)
    rows = _md_rows(el)
    isempty(rows) && return
    # Layout tables (no <th> header, common on legacy sites like HN) read far
    # better as plain flowing content than as a pipe table full of escaped junk.
    if !_md_has_th(rows)
        print(io, "\n\n")
        for row in rows
            cells = [c for c in row.children if c isa HTMLElement && Gumbo.tag(c) in (:td, :th)]
            for c in cells
                _md_children(io, c, ctx)
                print(io, " ")
            end
            print(io, "\n")
        end
        print(io, "\n")
        return
    end
    print(io, "\n\n")
    for (ri, row) in enumerate(rows)
        cells = [c for c in row.children if c isa HTMLElement && Gumbo.tag(c) in (:td, :th)]
        isempty(cells) && continue
        vals = [replace(strip(_md_clean(_md_inner(c, ctx))), "\n" => " ", "|" => "\\|") for c in cells]
        println(io, "| ", join(vals, " | "), " |")
        ri == 1 && println(io, "|", " --- |"^length(vals))
    end
    print(io, "\n")
end
