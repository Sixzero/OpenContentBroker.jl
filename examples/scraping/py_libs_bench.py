# file: bench_md_converters.py
import time, os, sys, pathlib, traceback, requests

URLS = [
    # "https://example.com/",
    # "https://www.wikipedia.org/",
    # "https://news.ycombinator.com/",
    "https://quotes.toscrape.com/tag/miracles/page/1/",
    "https://python.langchain.com/docs/integrations/document_transformers/markdownify/",
    "https://apify.com/store",
]

OUT = pathlib.Path("out_py")
OUT.mkdir(exist_ok=True)
HEADERS = {"User-Agent": "bench-md/1.0"}

def fetch(url):
    r = requests.get(url, headers=HEADERS, timeout=30)
    r.raise_for_status()
    return r.text, r.url

def save(name, text):
    (OUT / name).write_text(text, encoding="utf-8")

def bench(name, fn):
    t0 = time.perf_counter()
    ok = 0
    total_html_len = 0
    total_md_len = 0
    
    for url in URLS:
        html, final = fetch(url)
        html_len = len(html)
        total_html_len += html_len
        
        try:
            md = fn(html, final)
            md_len = len(md)
            total_md_len += md_len
            
            base = final.replace("https://", "").replace("http://", "").replace("/", "_")
            save(f"{base}.{name}.md", md)
            
            compression_ratio = md_len / html_len if html_len > 0 else 0
            print(f"  {final[:50]:50s} HTML: {html_len:6,} -> MD: {md_len:6,} ({compression_ratio:.1%})")
            
            ok += 1
        except Exception:
            print(f"  {final[:50]:50s} FAILED")
            traceback.print_exc()
    
    dt = time.perf_counter() - t0
    avg_compression = total_md_len / total_html_len if total_html_len > 0 else 0
    
    print(f"{name:12s} -> {ok}/{len(URLS)} pages in {dt:.2f}s ({ok/dt:.2f} pages/s)")
    print(f"             Total HTML: {total_html_len:,} -> Total MD: {total_md_len:,} (avg {avg_compression:.1%})")
    print()

# --- markdownify (MIT)
from markdownify import markdownify as _markdownify
def md_markdownify(html, url):
    # tune if you want: heading_style="ATX", strip=["script","style"]
    return _markdownify(html, heading_style="ATX")

# --- html2text (GPLv3)
try:
    import html2text
    h2t = html2text.HTML2Text()
    h2t.body_width = 0          # don't hard-wrap
    h2t.ignore_images = False
    h2t.ignore_links = False
    def md_html2text(html, url):
        return h2t.handle(html)
except Exception:
    md_html2text = None

# --- optional: pypandoc -> needs pandoc installed
try:
    import pypandoc
    def md_pandoc(html, url):
        return pypandoc.convert_text(html, "gfm", format="html")
except Exception:
    md_pandoc = None

if __name__ == "__main__":
    print("Output dir:", OUT.resolve())
    bench("markdownify", md_markdownify)
    if md_html2text:
        bench("html2text", md_html2text)
    else:
        print("(html2text not installed)")
    if md_pandoc:
        bench("pandoc", md_pandoc)
    else:
        print("(pandoc / pypandoc not installed)")
