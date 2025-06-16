using HTTP
using JSON3
using Dates
using OpenCacheLayer

# Base search result type
struct SearchResult <: OpenCacheLayer.AbstractMessage
    title::String
    url::String
    content::String
    score::Float64
    timestamp::DateTime
end

# Helper for common timestamp implementation
OpenCacheLayer.get_timestamp(result::SearchResult) = result.timestamp

# Abstract search adapter type
abstract type AbstractSearchAdapter <: OpenCacheLayer.ChatsLikeAdapter end
