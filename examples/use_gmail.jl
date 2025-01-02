using OpenCacheLayer
using OpenContentBroker
using DotEnv
using Dates

# Load environment variables from .env
DotEnv.load!()

# Get credentials from environment variables
credentials = Dict(
    "client_id" => get(ENV, "GMAIL_CLIENT_ID", ""),
    "client_secret" => get(ENV, "GMAIL_CLIENT_SECRET", "")
)

# Validate client credentials exist
all(!=(""), values(credentials)) || error("Missing Gmail client credentials in environment variables")

# Create adapter instance and it will handle authorization if needed
adapter = GmailAdapter(credentials)

# Wrap adapter with cache layer
cached_adapter = CacheLayer(adapter)

# Get messages from last 2 days - this will cache the results
messages = get_new_content(cached_adapter, now() - Day(2))

# Next time you run this with the same date, it will use cache and only fetch new messages

# Process each message
for msg in messages
    email = msg.processed_content
    println("Subject: $(email.subject)")
    println("From: $(email.from)")
    println("Body: $(email.body[1:min(100,length(email.body))])...")
    println("-" ^ 50)
end
