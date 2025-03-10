# Example TelegramAdapter implementation for testing
struct TelegramMessage <: AbstractMessage
    text::String
    chat_id::Int64
    raw_content::Vector{UInt8}    # Added raw content
    sender::String                # Added basic metadata
    recipients::Vector{String}    # Added basic metadata
    timestamp::DateTime           # Added timestamp
end

struct TelegramAdapter <: ChatsLikeAdapter
    config::AdapterConfig
    last_update_id::Union{Int, Nothing}
end

# Implement required interface methods
function get_content(adapter::TelegramAdapter, query::Dict)
    # Mock implementation
    raw = Vector{UInt8}("test message")
    return [
        TelegramMessage(
            "test",              # text
            123,                 # chat_id
            raw,                 # raw_content
            "user1",             # sender
            ["recipient1"],      # recipients
            now()               # timestamp
        )
    ]
end

function process_raw(adapter::TelegramAdapter, raw::Vector{UInt8})
    # Mock implementation
    return TelegramMessage(
        String(raw),        # text
        123,                # chat_id
        raw,                # raw_content
        "user1",            # sender
        ["recipient1"],     # recipients
        now()              # timestamp
    )
end

# Add implementation for get_timestamp
function OpenCacheLayer.get_timestamp(message::TelegramMessage)
    message.timestamp
end
