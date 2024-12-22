# Core types for content adapters
abstract type ContentAdapter{ContentType, MetadataType} end
abstract type MessageBasedAdapter{ContentType, MetadataType} <: ContentAdapter{ContentType, MetadataType} end
abstract type StatusBasedAdapter{ContentType, MetadataType} <: ContentAdapter{ContentType, MetadataType} end

# Base content item type
struct ContentItem{ContentType, MetadataType}
    id::String
    raw_content::Vector{UInt8}
    processed_content::ContentType
    metadata::MetadataType
    timestamp::DateTime
end

# Common metadata types
struct MessageMetadata
    source_id::String
    sender::String
    recipients::Vector{String}
    thread_id::Union{String, Nothing}
    timestamp::DateTime
end

struct StatusMetadata
    source_id::String
    last_checked::DateTime
    etag::Union{String, Nothing}
end

# Configuration type
struct AdapterConfig
    refresh_interval::Period
    retry_policy::Dict{String, Any}
    filters::Dict{String, Any}
end
