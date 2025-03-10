using OpenContentBroker
using OpenCacheLayer
using Dates

# Create a web adapter instance
adapter = RawWebAdapter(Dict(
    "User-Agent" => "OpenContentBroker.jl/0.1.0",
    "Accept" => "text/html,application/json"
), 
    cache_policy=RESPECT  # Use the enum here
)

# Wrap with cache layer
cached_adapter = DictCacheLayer(adapter)

# Function to demonstrate fetching and caching
function fetch_and_show(url)
    println("\nFetching: ", url)
    content = get_content(cached_adapter, url)
    
    println("ETag: ", something(content.etag, "none"))
    println("Last-Modified: ", something(content.last_modified, "none"))
    println("Cache-Control: ", something(content.cache_control, "none"))
    println("Content length: ", length(content.content), " bytes")
    println("-" ^ 50)
end

# Test with different URLs
urls = [
    "https://httpbin.org/cache/5",      # Sets max-age=5
    "https://httpbin.org/etag/test",    # Returns ETag
    "https://httpbin.org/cache",        # No caching headers
]

# First round - Initial fetches
println("Initial fetches:")
for url in urls
    @time fetch_and_show(url)
    sleep(0.1)  # Be nice to the server
end

# Second round - Should use cache where valid
println("\nSecond round (immediate):")
for url in urls
    @time fetch_and_show(url)
end

# Wait for cache to expire
println("\nWaiting 6 seconds for cache to expire...")
sleep(6)

# Third round - Should refresh expired content
println("\nThird round (after expiry):")
for url in urls
    @time fetch_and_show(url)
end

