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

# 4xx (bad key, no credits) won't fix itself; anything else (5xx, timeout, DNS) gets one retry.
is_transient(e) = !(e isa HTTP.StatusError && 400 <= e.status < 500)

"""
Call `f(key)` with each key in turn, returning the first success. Transient
errors are retried once per key. Rethrows the last error once every key failed,
so an exhausted quota falls through to the next.
"""
function try_keys(f::Function, keys::Vector{String}, name::String; retries::Int=1)
    isempty(keys) && error("No $name configured")
    for (i, key) in enumerate(keys)
        for attempt in 0:retries
            try
                return f(key)
            catch e
                retry = attempt < retries && is_transient(e)
                retry || i < length(keys) || rethrow()
                @warn "$name #$i failed, $(retry ? "retrying" : "trying next")" exception=e
                retry || break
                sleep(0.5)
            end
        end
    end
end
