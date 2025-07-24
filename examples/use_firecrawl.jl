using OpenContentBroker
using OpenCacheLayer
using EasyContext: execute, result2string

# Initialize FirecrawlAdapter with your API key
base_adapter = FirecrawlAdapter(
    api_key = get(ENV, "FIRECRAWL_API_KEY", ""),
    formats = ["markdown", "html"]
)
cached_adapter = DictCacheLayer(base_adapter)  # Changed to DictCacheLayer
# cached_adapter = base_adapter
# Example 1: Compare uncached vs cached scraping
url = "https://docs.firecrawl.dev/introduction"
url = "httpbin.org/html"

println("Example 1: Testing caching")
println("First call (uncached):")
@time content1 = get_content(cached_adapter, url)
println("Second call (should be cached):")
@time content2 = get_content(cached_adapter, url)
println("Content matches: ", content1.content == content2.content, "\n")

# Example 2: Using with WebContentTool (uses cached adapter by default)
# tool = WebContentTool(
#     url = "https://docs.firecrawl.dev/api-reference/introduction"
# )

# println("Example 2: Using WebContentTool with cached adapter")
# @time execute(tool)
# println(result2string(tool))

# Example 3: Compare with uncached tool
# uncached_tool = WebContentTool(
#     url = "https://docs.firecrawl.dev/api-reference/introduction"
# )

# println("\nExample 3: Using WebContentTool with uncached adapter")
# @time execute(uncached_tool)
# println("Results match: ", tool.result == uncached_tool.result)
