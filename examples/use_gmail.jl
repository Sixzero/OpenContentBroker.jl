using OpenContentBroker
using DotEnv

# Load environment variables from .env
DotEnv.load()

# Get credentials from environment variables
credentials = Dict(
    "client_id" => get(ENV, "GMAIL_CLIENT_ID", ""),
    "client_secret" => get(ENV, "GMAIL_CLIENT_SECRET", ""),
    "refresh_token" => get(ENV, "GMAIL_REFRESH_TOKEN", "")
)

# Validate credentials exist
all(!=(""), values(credentials)) || error("Missing Gmail credentials in environment variables")

# Create adapter instance
adapter = GmailAdapter(credentials)

# Get new messages
messages = get_new_content(adapter)

# Process each message
for msg in messages
    email = msg.processed_content
    println("Subject: $(email.subject)")
    println("From: $(email.from)")
    println("Body: $(email.body[1:min(100,length(email.body))])...")
    println("-" ^ 50)
end
