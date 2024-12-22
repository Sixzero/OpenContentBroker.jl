using HTTP
using JSON3
using Dates
using Base64
using URIs

# OAuth2 configuration for Gmail
const GMAIL_OAUTH_CONFIG = Dict(
    "auth_uri" => "https://accounts.google.com/o/oauth2/v2/auth",
    "token_uri" => "https://oauth2.googleapis.com/token",
    "scope" => "https://www.googleapis.com/auth/gmail.readonly",
    "redirect_uri" => "http://localhost:8080"
)

# Gmail specific message type
struct GmailMessage
    subject::String
    body::String
    from::String
    to::Vector{String}
    message_id::String
    thread_id::String
    labels::Vector{String}
end

struct GmailAdapter <: MessageBasedAdapter{GmailMessage, MessageMetadata}
    config::AdapterConfig
    oauth::OAuth2Config
    token::Ref{Union{OAuth2Token, Nothing}}
    token_storage::TokenStorage
    last_history_id::Union{String, Nothing}
end

# Updated constructor
function GmailAdapter(credentials::Dict{String, String}, token_storage::TokenStorage=EnvFileStorage())
    config = AdapterConfig(
        Minute(1),
        Dict("max_retries" => 3, "retry_delay" => 1),
        Dict("labels" => ["INBOX"], "max_results" => 100)
    )
    
    oauth = OAuth2Config(
        GMAIL_OAUTH_CONFIG["auth_uri"],
        GMAIL_OAUTH_CONFIG["token_uri"],
        GMAIL_OAUTH_CONFIG["scope"],
        GMAIL_OAUTH_CONFIG["redirect_uri"],
        credentials["client_id"],
        credentials["client_secret"]
    )
    
    GmailAdapter(config, oauth, Ref{Union{OAuth2Token, Nothing}}(nothing), token_storage, nothing)
end

# Token storage methods remain the same
function store_refresh_token!(adapter::GmailAdapter, token::String)
    store_token!(adapter.token_storage, "GMAIL_REFRESH_TOKEN", token)
end

function get_refresh_token(adapter::GmailAdapter)
    get_token(adapter.token_storage, "GMAIL_REFRESH_TOKEN")
end

# Simple token management
function ensure_token!(adapter::GmailAdapter)
    if isnothing(adapter.token[])
        refresh_token = get_refresh_token(adapter)
        isnothing(refresh_token) && throw(ArgumentError("No refresh token available"))
        adapter.token[] = refresh_access_token(adapter.oauth, refresh_token)
    end
    adapter.token[].access_token
end

"""
    authorize!(adapter::GmailAdapter) -> Nothing

Start OAuth2 authorization flow for Gmail.
"""
function authorize!(adapter::GmailAdapter)
    start_oauth_flow!(adapter.oauth) do token
        store_refresh_token!(adapter, token.refresh_token)
        adapter.token[] = token
    end
end

# Process raw Gmail message data
function process_raw(adapter::GmailAdapter, raw::Vector{UInt8})
    msg_data = JSON3.read(raw)
    
    # Extract headers
    headers = Dict(h.name => h.value for h in msg_data.payload.headers)
    
    # Process body (assuming text/plain for simplicity)
    body = ""
    if haskey(msg_data.payload, :body) && haskey(msg_data.payload.body, :data)
        body = String(base64decode(replace(msg_data.payload.body.data, '-'=>'+', '_'=>'/')))
    end
    
    GmailMessage(
        get(headers, "Subject", ""),
        body,
        get(headers, "From", ""),
        split(get(headers, "To", ""), ","),
        msg_data.id,
        msg_data.threadId,
        msg_data.labelIds
    )
end

# Validate content
function validate_content(adapter::GmailAdapter, content::ContentItem)
    # Check if message still exists and labels haven't changed
    # For mock, always return true
    true
end

# Get new messages since last check
function get_new_content(adapter::GmailAdapter)
    # In real implementation, would use Gmail API's history.list or messages.list
    # For now, return mock data
    mock_message = Dict(
        "id" => "msg123",
        "threadId" => "thread123",
        "labelIds" => ["INBOX"],
        "payload" => Dict(
            "headers" => [
                Dict("name" => "Subject", "value" => "Test Email"),
                Dict("name" => "From", "value" => "sender@example.com"),
                Dict("name" => "To", "value" => "recipient@example.com")
            ],
            "body" => Dict(
                "data" => base64encode("This is a test email body.")
            )
        )
    )
    
    raw_content = Vector{UInt8}(JSON3.write(mock_message))
    processed = process_raw(adapter, raw_content)
    
    [ContentItem(
        processed.message_id,
        raw_content,
        processed,
        MessageMetadata(
            "gmail",
            processed.from,
            processed.to,
            processed.thread_id,
            now()
        ),
        now()
    )]
end

# Implement base get_content for specific queries
function get_content(adapter::GmailAdapter, query::Dict)
    # In real implementation, would use Gmail API's messages.list with query parameters
    # For now, delegate to get_new_content
    get_new_content(adapter)
end
