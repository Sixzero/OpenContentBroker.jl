using OpenContentBroker
using DotEnv
using Dates
using EasyContext: create_voyage_embedder, TwoLayerRAG, ReduceGPTReranker, TopK, BM25Embedder, execute


# Load environment variables from .env
DotEnv.load!()

# Get credentials from environment variables
credentials = Dict(
    "client_id" => get(ENV, "GMAIL_CLIENT_ID", ""),
    "client_secret" => get(ENV, "GMAIL_CLIENT_SECRET", "")
)

# Validate client credentials exist
all(!=(""), values(credentials)) || error("Missing Gmail client credentials in environment variables")

# Create the adapter
gmail_adapter = GmailAdapter(
    credentials,
    "tamashavlik@diabtrend.com",
)

# Create tool with default RAG pipeline
gmail_tool = GmailSearchTool(
    gmail_adapter=gmail_adapter,
    query="Milyen fontos user reklamációk érkeztek?"
)

# Example search with semantic reranking
println("\nSearching emails about project deadlines:")
println("=" ^ 50)

# Execute the tool with parameters
execute(gmail_tool; 
    from=now() - Week(2),    # Last 2 weeks
    max_results=100,         # Get more results for better semantic search
    labels=["INBOX"]
)

# Print results in human-readable format
for (i, (email, content)) in enumerate(zip(gmail_tool.emails, gmail_tool.search_results))
    println("""
    Email #$i:
    Subject: $(email.subject)
    From: $(email.from)
    Date: $(email.date)
    
    $(first(content, 300))...
    
    $(repeat("-", 50))
    """)
end
