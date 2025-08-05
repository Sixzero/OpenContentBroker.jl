using OpenContentBroker
using OpenContentBroker: CrawleeAdapter
using OpenCacheLayer

# Create a Crawlee adapter
crawlee_adapter = CrawleeAdapter(
    use_readability=true,  # Use Mozilla Readability for cleaner content
)
scrapy_adapter = ScrapyAdapter()
fire_adapter = FirecrawlAdapter(
    api_key = get(ENV, "FIRECRAWL_API_KEY", ""),
    formats = ["markdown", "html"]
)
md_adapter = MarkdownifyAdapter(
    headers=Dict("User-Agent" => "Mozilla/5.0 (compatible; JuliaMarkdownifyBot)"),
    timeout=30
)

# Test with a URL
url = "https://quotes.toscrape.com/"
url = "https://quotes.toscrape.com/tag/change/page/1/"
url = "https://quotes.toscrape.com/tag/abilities/page/1/"
url = "https://quotes.toscrape.com/tag/miracle/page/1/"
url = "https://quotes.toscrape.com/tag/miracles/page/1/"
url = "https://apify.com/store"
url = "https://python.langchain.com/docs/integrations/document_transformers/markdownify/"
# url = "https://example.com"
println("Scraping: $url")

content_md = @time get_content(md_adapter, url)
println("Content Scrapy length: $(length(content_md.content))")
println(content_md.content[1:min(1000, end)])

# content_scy = @time get_content(scrapy_adapter, url)
# println("Content Scrapy length: $(length(content_scy.content))")
# println(content_scy.content[1:min(10000,end)])

# content_crw = @time get_content(crawlee_adapter, url)
# println("Content length: $(length(content_crw.content))")
# println(content_crw.content[1:min(10000, end)])

# content_fire = @time get_content(fire_adapter, url)
# println("Content FireCrawl: $(length(content_fire.content))")
# println(content.content)

;
#%%
println(occursin("Code Pioneer", content_md.content))
println(occursin("Code Pioneer", content_scy.content))
println(occursin("Code Pioneer", content_crw.content))