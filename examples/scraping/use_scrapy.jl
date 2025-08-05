using OpenContentBroker
using OpenContentBroker: ScrapyAdapter
using OpenCacheLayer

# Create a Scrapy adapter
scrapy_adapter = ScrapyAdapter(
    user_agent="Mozilla/5.0 (compatible; JuliaBot)",
    remove_elements=["script", "style", "nav", "footer", ".ads"]
)

# Test with a URL
url = "https://quotes.toscrape.com/tag/change/page/1/"
println("Scraping with Scrapy: $url")

content = @time get_content(scrapy_adapter, url)
println("Content length: $(length(content.content))")
println("First 1000 chars:")
println(content.content[1:min(1000, length(content.content))])

if haskey(content.metadata, :title)
    println("Title: $(content.metadata[:title])")
end