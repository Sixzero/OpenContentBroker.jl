"""Extract a PDF's text layer. PDF on stdin, text on stdout, "pages=<n>/<total>" on stderr.

Run as a subprocess on purpose: an in-process CPython holds the GIL for the whole
extraction, which can stall Julia's scheduler when tools run in @async tasks on a
multithreaded agent. See binary_content.jl.
"""
import sys

import pymupdf


def main() -> int:
    max_pages, max_chars = int(sys.argv[1]), int(sys.argv[2])
    doc = pymupdf.open(stream=sys.stdin.buffer.read(), filetype="pdf")
    try:
        parts, nchars, pages = [], 0, 0
        for i in range(min(doc.page_count, max_pages)):
            text = doc[i].get_text()
            parts.append(text)
            nchars += len(text)
            pages += 1
            if nchars > max_chars:  # caller truncates precisely; just stop early
                break
        sys.stdout.write("\n\n".join(parts))
        print(f"pages={pages}/{doc.page_count}", file=sys.stderr)
    finally:
        doc.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
