using OpenContentBroker
using OpenContentBroker: sniff_mime, pdf_to_text, PDF_MAGIC, _is_textual_mime
using OpenCacheLayer
using Test
using JSON3

const RUN_NET = get(ENV, "OCB_NET_TESTS", "false") == "true"

@testset "binary content handling" begin

    @testset "sniff_mime" begin
        hdr(v) = ["Content-Type" => v]

        # Magic bytes win over a (mislabeled) header
        @test sniff_mime(hdr("text/html"), Vector{UInt8}("%PDF-1.7\nfoo")) == "application/pdf"
        @test sniff_mime([], Vector{UInt8}("%PDF-1.4")) == "application/pdf"
        @test sniff_mime(hdr("application/pdf"), Vector{UInt8}("%PDF-1.7")) == "application/pdf"

        # Normal textual pages
        @test sniff_mime(hdr("text/html; charset=utf-8"), Vector{UInt8}("<html>hi</html>")) == "text/html"
        @test sniff_mime(hdr("application/json"), Vector{UInt8}("{\"a\":1}")) == "application/json"
        @test sniff_mime(hdr("application/xhtml+xml"), Vector{UInt8}("<html/>")) == "application/xhtml+xml"
        @test sniff_mime([], Vector{UInt8}("<html>hi</html>")) == "text/html"

        # Declared binaries stay binary
        @test sniff_mime(hdr("image/png"), UInt8[0x89, 0x50, 0x4e, 0x47]) == "image/png"
        @test sniff_mime(hdr("application/zip"), Vector{UInt8}("PK\x03\x04")) == "application/zip"

        # NUL early in the body beats a lying textual header — binary is binary.
        @test sniff_mime([], UInt8[0x00, 0x01, 0x02]) == "application/octet-stream"
        @test sniff_mime(hdr("text/plain"), UInt8[0x00, 0x01, 0x02]) == "application/octet-stream"
        # PDF magic found within the sniff window (spec allows leading junk)
        @test sniff_mime(hdr("text/html"), Vector{UInt8}("\n\n junk %PDF-1.5")) == "application/pdf"
    end

    @testset "_is_textual_mime" begin
        @test _is_textual_mime("text/html")
        @test _is_textual_mime("text/plain")
        @test _is_textual_mime("application/json")
        @test _is_textual_mime("application/xhtml+xml")
        @test !_is_textual_mime("application/pdf")
        @test !_is_textual_mime("image/png")
        @test !_is_textual_mime("application/octet-stream")
    end

    @testset "truncate_chars" begin
        tc = OpenContentBroker.truncate_chars
        @test tc("abc", 10) == "abc"
        @test tc("abcdef", 3) == "abc …[truncated]"
        # char-boundary safe on multibyte input
        @test tc("áéíóú", 2) == "áé …[truncated]"
    end

    @testset "truncate_bytes" begin
        tb = OpenContentBroker.truncate_bytes
        mark = OpenContentBroker.TRUNCATION_MARK
        @test tb("abc", 10) == "abc"                       # short input untouched
        @test tb("hello world, quite long indeed", 20) == "hello" * mark
        # hard byte cap INCLUDES the marker; cut lands on a char boundary
        for s in ["日本語のテキスト"^10, "🎉😀🚀"^15, "áéíóú"^20, "mix 日本 é 🎉"^8]
            for n in (sizeof(mark), 25, 40, 100)
                r = tb(s, n)
                @test isvalid(r)
                @test sizeof(r) <= n
                @test endswith(r, mark)
            end
        end
        # degenerate cap smaller than the marker: returns just the marker
        @test tb("abcdef", 3) == mark
    end

    @testset "bounded_error" begin
        be = OpenContentBroker.bounded_error
        # exception payloads embedding a whole response body must never escape
        huge = "Error: " * "x"^3_000_000
        @test length(be(huge)) <= OpenContentBroker.MAX_ERROR_CHARS + length(" …[truncated]")
        @test endswith(be(huge), "…[truncated]")
        @test be("short error") == "short error"
    end

    # Minimal single-page PDF built by pymupdf itself — no network, no fixture file.
    @testset "pdf_to_text" begin
        PC = OpenContentBroker.PythonCall
        m = OpenContentBroker.ensure_pymupdf()
        mkpdf(npages) = begin
            doc = m.open()
            for i in 1:npages
                p = doc.new_page()
                p.insert_text(PC.pytuple((72, 72)), "PAGE $i MARKER")
            end
            bytes = PC.pyconvert(Vector{UInt8}, doc.tobytes())
            doc.close()
            bytes
        end

        pdf = mkpdf(3)
        @test sniff_mime([], pdf) == "application/pdf"
        text = pdf_to_text(pdf)
        @test occursin("PAGE 1 MARKER", text)
        @test occursin("PAGE 3 MARKER", text)

        # page cap
        capped = pdf_to_text(mkpdf(5); max_pages = 2)
        @test occursin("PAGE 2 MARKER", capped)
        @test !occursin("PAGE 4 MARKER", capped)
        @test occursin("[truncated", capped)

        # char cap: body cut to ~10 chars; markers (char + page truncation) remain small
        short = pdf_to_text(pdf; max_chars = 10)
        @test length(short) < 100
        @test occursin("[truncated]", short)
        @test occursin("pages extracted", short)  # char cap stopped extraction early
    end

    @testset "adapter caps payload (network)" begin
        if !RUN_NET
            @info "skipping network test (set OCB_NET_TESTS=true to run)"
        else
            a = OpenContentBroker.MarkdownifyAdapter()
            url = "https://www.neb.com/-/media/nebus/files/manuals/manuale1601.pdf"
            c = OpenCacheLayer.get_content(a, url)
            @test !haskey(c.metadata, :error)
            @test get(c.metadata, :mime, "") == "application/pdf"
            @test occursin("Golden Gate", c.content)
            # The whole point: the tool result must stay tiny, never MBs.
            @test sizeof(JSON3.write(c.content)) < 200_000
        end
    end
end
