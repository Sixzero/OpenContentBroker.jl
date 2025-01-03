using HTTP
using JSON3
using Dates
using Base64
using URIs
using OpenCacheLayer  # Add this to use the base types
# Add this import specifically for the get_new_content function
import OpenCacheLayer: get_new_content


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
    date::DateTime
end

struct GmailAdapter <: OpenCacheLayer.ChatsLikeAdapter
    config::AdapterConfig
    token_manager::OAuth2TokenManager
end

# Updated constructor without last_history_id
function GmailAdapter(credentials::Dict{String, String}, token_storage::TokenStorage=FileStorage("OpenContentBroker"))
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
    
    token_manager = OAuth2TokenManager(oauth, token_storage)
    GmailAdapter(config, token_manager)
end

# Remove token-related methods from GmailAdapter
function ensure_token!(adapter::GmailAdapter)
    ensure_access_token!(adapter.token_manager)
end

# Add this new method
function authorize!(adapter::GmailAdapter)
    authorize!(adapter.token_manager)
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
    
    # Extract message date from internalDate field (milliseconds since epoch)
    timestamp = try
        unix2datetime(parse(Int, msg_data.internalDate) / 1000)
    catch
        # Fallback to Date header if internalDate fails
        try
            DateTime(get(headers, "Date", ""), dateformat"e, d u y H:M:S Z")
        catch
            now()  # Final fallback
        end
    end
    
    GmailMessage(
        get(headers, "Subject", ""),
        body,
        get(headers, "From", ""),
        split(get(headers, "To", ""), ","),
        msg_data.id,
        msg_data.threadId,
        msg_data.labelIds,
        timestamp
    )
end

# Validate content
function validate_content(adapter::GmailAdapter, content::ContentItem)
    # Check if message still exists and labels haven't changed
    # For mock, always return true
    true
end

const GMAIL_API_BASE = "https://www.googleapis.com/gmail/v1"

# Get new messages since last check
function OpenCacheLayer.get_new_content(adapter::GmailAdapter; from::DateTime=now() - Day(1), to::Union{DateTime,Nothing}=nothing)
    access_token = ensure_token!(adapter)
    
    headers = [
        "Authorization" => "Bearer $access_token",
        "Accept" => "application/json"
    ]
    
    # Convert DateTime to Unix timestamp (seconds since epoch)
    after_ts = floor(Int, datetime2unix(from))
    before_ts = isnothing(to) ? nothing : floor(Int, datetime2unix(to))
    
    query = Dict(
        "maxResults" => get(adapter.config.filters, "max_results", 100),
        "labelIds" => join(get(adapter.config.filters, "labels", ["INBOX"]), ","),
        "q" => isnothing(before_ts) ? 
            "after:$(after_ts)" : 
            "after:$(after_ts) before:$(before_ts)"
    )
    
    response = HTTP.get(
        "$GMAIL_API_BASE/users/me/messages?$(URIs.escapeuri(query))",
        headers
    )
    
    messages_data = JSON3.read(response.body)
    
    # Early return for empty results
    (!haskey(messages_data, :messages) || isnothing(messages_data.messages)) && return ContentItem[]
    
    # Process messages in parallel with rate limiting
    items = asyncmap(messages_data.messages; ntasks=GMAIL_MAX_PARALLEL) do msg
        # Rate limiting sleep
        sleep(1/GMAIL_RATE_LIMIT)
        
        msg_response = HTTP.get(
            "$GMAIL_API_BASE/users/me/messages/$(msg.id)?format=full",
            headers
        )
        
        raw_content = msg_response.body
        processed = process_raw(adapter, raw_content)
        
        ContentItem(
            processed.message_id,
            raw_content,
            processed,
            MessageMetadata(
                "gmail",
                processed.from,
                processed.to,
                processed.thread_id,
                processed.date
            ),
            processed.date
        )
    end
    
    # Sort by timestamp before returning
    sort!(items, by = x -> x.timestamp)
    items
end

# Implement base get_content for specific queries
function get_content(adapter::GmailAdapter, query::Dict)
    from = get(query, "from", now() - Day(1))
    get_new_content(adapter, from)
end

# Add after the adapter struct definition
function OpenCacheLayer.get_adapter_hash(adapter::GmailAdapter)
    # Use client_id as unique identifier for the credentials
    adapter.token_manager.config.client_id
end

# Add support for time range queries
OpenCacheLayer.supports_time_range(::GmailAdapter) = true
