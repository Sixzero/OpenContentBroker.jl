using HTTP
using JSON3
using Dates
using Base64
using URIs
using OpenCacheLayer
# Add this to use the base types
# Add this import specifically for the get_new_content function

# Rate limiting constants
const GMAIL_MAX_PARALLEL = 3  # Maximum parallel requests
const GMAIL_RATE_LIMIT = 5    # Requests per second

# OAuth2 configuration for Gmail - update scope to include both Gmail and user info
const GMAIL_OAUTH_CONFIG = Dict(
    "auth_uri" => "https://accounts.google.com/o/oauth2/v2/auth",
    "token_uri" => "https://oauth2.googleapis.com/token",
    "scope" => "https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/userinfo.email https://mail.google.com/",
    "redirect_uri" => "http://localhost:8080"
)

# Gmail specific message type
struct GmailMessage <: OpenCacheLayer.AbstractMessage
    subject::String
    body::String
    from::String
    to::Vector{String}
    message_id::String
    thread_id::String
    labels::Vector{String}
    date::DateTime
    raw_content::Vector{UInt8}    # Add raw content storage
end

struct GmailAdapter <: OpenCacheLayer.ChatsLikeAdapter
    token_manager::OAuth2TokenManager
    email::String  # Required email for token identification
end

function GmailAdapter(credentials::Dict{String, String}, email::String, token_storage::TokenStorage=FileStorage("OpenContentBroker"))
    oauth = OAuth2Config(
        GMAIL_OAUTH_CONFIG["auth_uri"],
        GMAIL_OAUTH_CONFIG["token_uri"],
        GMAIL_OAUTH_CONFIG["scope"],
        GMAIL_OAUTH_CONFIG["redirect_uri"],
        credentials["client_id"],
        credentials["client_secret"]
    )
    
    GmailAdapter(OAuth2TokenManager(oauth, token_storage), email)
end

# Remove token-related methods from GmailAdapter
"""
Start Gmail-specific OAuth2 authorization flow with email verification
"""
function authorize!(adapter::GmailAdapter)
    authorize!(adapter.token_manager; 
        service_name="Gmail", 
        filename="$(adapter.email).env",
        validation_fn=(token) -> verify_user_email(token, adapter.email)
    )
end
"""
Force a new authorization flow by clearing stored tokens first
"""
function force_authorize!(adapter::GmailAdapter)
    # Remove the stored token file
    token_path = get_token_path(adapter.token_manager.storage; filename="$(adapter.email).env")
    isfile(token_path) && rm(token_path)
    
    # Reset the current token
    adapter.token_manager.token[] = nothing
    
    # Start fresh authorization
    authorize!(adapter)
end

# Simplify ensure_token! to use the new authorize!
function ensure_token!(adapter::GmailAdapter)
    refresh_token = get_token(adapter.token_manager.storage; filename="$(adapter.email).env")
    
    if isnothing(refresh_token)
        @info "No refresh token found for $(adapter.email). Starting authorization flow..."
        authorize!(adapter)
        refresh_token = get_token(adapter.token_manager.storage; filename="$(adapter.email).env")
    end
    
    try
        adapter.token_manager.token[] = refresh_access_token(adapter.token_manager.config, refresh_token)
        verify_user_email(adapter.token_manager.token[].access_token, adapter.email)
    catch e
        if e isa HTTP.ExceptionRequest.StatusError && e.status in [400, 401]
            @info "Refresh token expired for $(adapter.email). Starting authorization flow..."
            authorize!(adapter)
            refresh_token = get_token(adapter.token_manager.storage; filename="$(adapter.email).env")
            adapter.token_manager.token[] = refresh_access_token(adapter.token_manager.config, refresh_token)
        else
            rethrow(e)
        end
    end
    
    adapter.token_manager.token[].access_token
end

# Function to verify user email matches requested one
function verify_user_email(access_token::String, expected_email::String)
    try
        response = HTTP.get(
            "https://www.googleapis.com/oauth2/v2/userinfo",
            ["Authorization" => "Bearer $access_token"]
        )
        data = JSON3.read(response.body)
        data.email == expected_email || error("Authenticated email ($(data.email)) doesn't match requested email ($(expected_email))")
        true
    catch e
        @error "Failed to verify user email" exception=e
        rethrow(e)
    end
end


"""
    process_raw(adapter::ContentAdapter, raw::Vector{UInt8}) -> ContentType

Process raw Gmail message data into structured format.
"""
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
        timestamp,
        raw                        # Store the raw content
    )
end

const GMAIL_API_BASE = "https://www.googleapis.com/gmail/v1"

# Get new messages since last check
function OpenCacheLayer.get_content(adapter::GmailAdapter; 
    from::DateTime=now() - Day(1), 
    to::Union{DateTime,Nothing}=nothing, 
    max_results::Int=100,
    labels::Vector{String}=["INBOX"]
)
    access_token = ensure_token!(adapter)
    
    headers = [
        "Authorization" => "Bearer $access_token",
        "Accept" => "application/json"
    ]
    
    after_ts = floor(Int, datetime2unix(from))
    before_ts = isnothing(to) ? nothing : floor(Int, datetime2unix(to))
    
    query = Dict(
        "maxResults" => max_results,
        "labelIds" => join(labels, ","),
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
    (!haskey(messages_data, :messages) || isnothing(messages_data.messages)) && return Vector{GmailMessage}()
    
    # Process messages in parallel with rate limiting
    messages = asyncmap(messages_data.messages; ntasks=GMAIL_MAX_PARALLEL) do msg
        # Rate limiting sleep
        sleep(1/GMAIL_RATE_LIMIT)
        
        msg_response = HTTP.get(
            "$GMAIL_API_BASE/users/me/messages/$(msg.id)?format=full",
            headers
        )
        
        process_raw(adapter, msg_response.body)
    end
    
    # Sort by timestamp before returning
    sort!(messages, by = x -> x.date)
    messages
end

# Update the base get_content for specific queries
function OpenCacheLayer.get_content(adapter::GmailAdapter, query::Dict)
    from = get(query, "from", now() - Day(1))
    max_results = get(query, "max_results", 100)
    labels = get(query, "labels", ["INBOX"])
    get_content(adapter; from=from, max_results=max_results, labels=labels)
end

# Add after the adapter struct definition
function OpenCacheLayer.get_adapter_hash(adapter::GmailAdapter)
    # Use client_id as unique identifier for the credentials
    "$(adapter.token_manager.config.client_id)_$(adapter.email)"
end

# Add support for time range queries
OpenCacheLayer.supports_time_range(::GmailAdapter) = true

# Add implementation for get_timestamp
function OpenCacheLayer.get_timestamp(message::GmailMessage)
    message.date
end

# Add after get_timestamp implementation
function OpenCacheLayer.get_unique_id(message::GmailMessage)
    message.message_id
end
