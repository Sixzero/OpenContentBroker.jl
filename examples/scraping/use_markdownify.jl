using OpenContentBroker
using OpenCacheLayer

# Create the adapter with custom headers
adapter = MarkdownifyAdapter(
    headers=Dict("User-Agent" => "Mozilla/5.0 (compatible; JuliaMarkdownifyBot)"),
    timeout=30
)

# Test URLs from the Python timing script
urls = [
    "https://quotes.toscrape.com/tag/miracles/page/1/",
    "https://python.langchain.com/docs/integrations/document_transformers/markdownify/",
]

println("🕐 Julia Markdownify Adapter Test")
println("=" ^ 40)

for url in urls
    println("\nTesting: $url")
    
    @time begin
        content = get_content(adapter, url)
        
        if haskey(content.metadata, :error)
            println("❌ Error: $(content.metadata[:error])")
        else
            println("⏱️  Success!")
            println("📄 HTML length: $(get(content.metadata, :html_length, 0)) chars")
            println("📝 Markdown length: $(get(content.metadata, :markdown_length, 0)) chars")
            if haskey(content.metadata, :compression_ratio)
                println("📊 Compression ratio: $(round(content.metadata[:compression_ratio] * 100, digits=1))%")
            end
            
            # Show first 200 chars of markdown
            preview = first(content.content, min(200, length(content.content)))
            preview = replace(preview, '\n' => "\\n")
            println("🔍 Preview: $preview...")
        end
    end
end

# Test caching behavior
println("\n🔄 Testing cache behavior...")
@time content1 = get_content(adapter, urls[1])
@time content2 = get_content(adapter, urls[1])  # Should be faster due to caching