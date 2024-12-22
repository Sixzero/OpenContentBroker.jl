using OpenContentBroker
using DotEnv

DotEnv.load!()

client_id = get(ENV, "GMAIL_CLIENT_ID", "")
client_secret = get(ENV, "GMAIL_CLIENT_SECRET", "")

isempty(client_id) && error("Set GMAIL_CLIENT_ID env variable")
isempty(client_secret) && error("Set GMAIL_CLIENT_SECRET env variable")

# Create adapter with default storage
adapter = GmailAdapter(Dict(
    "client_id" => client_id,
    "client_secret" => client_secret,
    "refresh_token" => ""
))

# Start authorization flow
authorize!(adapter)

