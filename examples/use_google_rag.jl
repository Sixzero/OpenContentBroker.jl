using OpenContentBroker
using OpenCacheLayer

# Initialize the adapter with default settings
adapter = GoogleRAGAdapter(
    # max_results=10  # Limit to top 3 results for faster testing
)

# Test query
query = "What is the privacy policy of Gwen Alibaba do they use data for training?"
query = "\"gwen alibaba cloud model privacy policy data usage training\""
query = "gwen alibaba cloud model privacy policy data usage training"
query = "MITTZON ikea emelő asztal gombok pirosan villog"

println("Searching and analyzing content for: $query")
println("This may take a minute as it needs to:")
println("1. Search Google")
println("2. Scrape each result")
println("3. Process and rank content chunks")
println("-" ^ 50)

# Get results
results = OpenCacheLayer.get_content(adapter, query)

# Display results
println("\nTop relevant content chunks:")
for (i, result) in enumerate(results.results)
    println("\n[$i] Source: $(string(result.url))")
    println("Content snippet:")
    println("-" ^ 30)
    println(length(result.content))
    println("-" ^ 30)
end
