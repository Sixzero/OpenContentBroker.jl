# Example TelegramAdapter implementation for testing
struct TelegramMessage
    text::String
    chat_id::Int64
end

struct TelegramAdapter <: MessageBasedAdapter{TelegramMessage, MessageMetadata}
    config::AdapterConfig
    last_update_id::Union{Int, Nothing}
end

# Implement required interface methods
function get_content(adapter::TelegramAdapter, query::Dict)
    # Mock implementation
    items = ContentItem[]
    push!(items, ContentItem(
        "msg1",
        Vector{UInt8}("test message"),
        TelegramMessage("test", 123),
        MessageMetadata(
            "telegram1",
            "user1",
            ["recipient1"],
            nothing,
            now()
        ),
        now()
    ))
    return items
end

function process_raw(adapter::TelegramAdapter, raw::Vector{UInt8})
    # Mock implementation
    return TelegramMessage(String(raw), 123)
end

function validate_content(adapter::TelegramAdapter, content::ContentItem)
    # Mock implementation
    return true
end

function get_new_content(adapter::TelegramAdapter)
    # Mock implementation
    return get_content(adapter, Dict())
end
