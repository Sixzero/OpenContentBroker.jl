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

# Create adapter instance with specific email
adapter = GmailAdapter(
    credentials,
    "tamashavlik@diabtrend.com",
)

# Wrap adapter with cache layer
cached_adapter = VectorCacheLayer(adapter)

# Get messages from last 2 days with custom labels and max_results
messages = get_content(cached_adapter; 
    from=now() - Hour(20), 
    max_results=50, 
    labels=["INBOX", ]
)

# Next time you run this with the same date, it will use cache and only fetch new messages

# Process each message
for email in messages
    println("Subject: $(email.subject)")
    println("From: $(email.date) $(email.from)")
    # println("Body: $(email.body[1:min(100,length(email.body))])...")
    println("-" ^ 50)
end
#%%
# in case we would need reauthrization, because permission issues.
using OpenContentBroker: force_authorize!
force_authorize!(adapter)