# WebFetch: pure-Julia HTML→Markdown — findings (2026-08-18)

## Mi történt

A `MarkdownifyAdapter` a `pyimport("markdownify")`-t (PythonCall/CondaPkg) használta
HTML→Markdown konverzióra. Lecseréltük tiszta Julia implementációra
(`src/adapters/scraping/html_to_markdown.jl`, Gumbo-alapú rekurzív renderer).

## Benchmark (min of 5 run, JIT warmup után, valós oldalak)

| Oldal | HTML | Julia | py-markdownify | Speedup |
|---|---|---|---|---|
| julialang.org | 61 kB | 5.2 ms | 38 ms | 7.3× |
| news.ycombinator.com | 35 kB | 3.2 ms | 31 ms | 9.7× |
| Wikipedia (Julia lang) | 771 kB | 42 ms | 294 ms | 7.1× |
| docs.julialang.org (async) | 42 kB | 3.5 ms | 28 ms | 8.1× |
| github.com/JuliaLang/julia | 384 kB | 16 ms | 164 ms | 10.3× |
| index.hu (címlap) | 537 kB | 25 ms | 173 ms | 6.9× |
| index.hu/belfold | 126 kB | 6.5 ms | 33 ms | 5.1× |
| telex.hu | 744 kB | 28 ms | 110 ms | 3.9× |
| simonwillison.net | 106 kB | 7 ms | 49 ms | 7.0× |
| karpathy blogpost | 34 kB | 2.2 ms | 11 ms | 4.9× |

**4–10× gyorsabb**, plusz megszűnik a hidegindításos pyimport/CondaPkg init (~s nagyságrend).

## Minőség

Headings/links/code blocks/table rows gyakorlatilag azonosak (±1–3%) minden oldalon.
Ahol eltér, a Julia kimenet a jobb:

- **Link `title="..."` attribútumokat eldobjuk** — a py megtartotta; Wikipédián ez
  +22 kB (+2800 szó) tiszta zaj volt, index.hu-n +4000 szó (410 title-attr).
  → ~15–20%-kal kevesebb LLM-token ugyanazért az információért.
- **Layout table-ök (nincs `<th>`, pl. HN, index.hu)**: a py escaped pipe-katyvaszt
  csinált (`\| \| --- \|`); mi folyó szövegként rendereljük.
- Magyar ékezetes tartalom hibátlan (charset detektálás a `markdownify_adapter.jl`-ben
  változatlan: Content-Type / meta charset → UTF-8/Latin-1 fallback).
- Karpathy-blogpost kódblokkjai (Python REPL formázás) bitre pontosan átjönnek.

## Fontos részletek

- **Cache hash bump**: `MARKDOWNIFY` → `MARKDOWNIFY_JL`, hogy a DictCacheLayer ne
  szolgáljon ki régi python-konvertált tartalmat. Cache-teszteléskor erre figyelni!
- A SPA-fallback (`extract_static_content`: title/meta/JSON-LD regex a nyers HTML-en)
  változatlan és működik (react.dev ✓).
- PythonCall dep marad, de már csak gitingest + imap használja.
- `<head>`-et komplett dobjuk, a `<title>`-t regex-szel emeljük ki (mint a py tette).

## Mellékes finding ugyanebből a munkamenetből (OpenRouter.jl)

Az api.anthropic.com elkezdte tiszteletben tartani az `Accept-Encoding: gzip`-et
**streaming** (SSE) válaszokon is. A HTTP.jl `HTTP.open` nem dekódol automatikusan
→ minden direkt Anthropic stream `EOF before done marker`-rel halt. Fix:
OpenRouter.jl `_open_sse_stream` mostantól `Accept-Encoding: identity`-t kér
(commit `9153dd6`). A cliproxyapi-s út (setup_cli_proxy! mutate=true) nem volt
érintett, mert a proxy nem tömörít.
