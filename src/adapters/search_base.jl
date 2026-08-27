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

"""
Collect `\$PREFIX`, `\$PREFIX_2`, `\$PREFIX_3`, ... from ENV until the first gap.
Empty values are skipped, so an exhausted key can be blanked without renumbering.
"""
function env_key_pool(prefix::String)
    keys = String[]
    for i in 1:100
        name = i == 1 ? prefix : "$(prefix)_$(i)"
        haskey(ENV, name) || break
        isempty(ENV[name]) || push!(keys, ENV[name])
    end
    keys
end

"""
Call `f(key)` with each key in turn, returning the first success. Rethrows the
last error once every key failed, so an exhausted quota falls through to the next.
"""
function try_keys(f::Function, keys::Vector{String}, name::String)
    isempty(keys) && error("No $name configured")
    for (i, key) in enumerate(keys)
        try
            return f(key)
        catch e
            i == length(keys) && rethrow()
            @warn "$name #$i failed, trying next" exception=e
        end
    end
end
