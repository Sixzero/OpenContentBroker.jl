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

# 4xx (bad key, no credits) won't fix itself; 5xx/408/429/transport errors get one retry.
is_transient(e::HTTP.StatusError) = e.status >= 500 || e.status in (408, 429)
is_transient(e::HTTP.RequestError) = true
is_transient(e::InterruptException) = false
is_transient(e) = false

# Never log the raw exception: HTTP.RequestError echoes the request incl. API-key headers/URLs.
error_brief(e::HTTP.StatusError) = "HTTP $(e.status)"
error_brief(e::HTTP.RequestError) = "transport: $(typeof(e.error))"
error_brief(e) = string(typeof(e))

"""
Called as `f(name, err)` when every key of `name` failed (or none configured).
Hosts can set this to alert operators; default: no-op.
"""
const ON_KEYS_EXHAUSTED = Ref{Function}((name, err) -> nothing)

function keys_exhausted(name, err)
    try ON_KEYS_EXHAUSTED[](name, err) catch e; @warn "ON_KEYS_EXHAUSTED hook failed" error=error_brief(e) end
    # Sanitized: the raw error would surface the request (incl. key) in tool output.
    error("$name: all keys failed ($(error_brief(err)))")
end

"""
Call `f(key)` with each key in turn, returning the first success. Transient
errors are retried once per key. Once every key failed, fires `ON_KEYS_EXHAUSTED`
and throws a sanitized ErrorException.
"""
function try_keys(f::Function, keys::Vector{String}, name::String; retries::Int=1)
    isempty(keys) && keys_exhausted(name, ErrorException("No $name configured"))
    for (i, key) in enumerate(keys)
        for attempt in 0:retries
            try
                return f(key)
            catch e
                retry = attempt < retries && is_transient(e)
                retry || i < length(keys) || keys_exhausted(name, e)
                e isa InterruptException && rethrow()
                @warn "$name #$i failed, $(retry ? "retrying" : "trying next")" error=error_brief(e)
                retry || break
                sleep(0.5)
            end
        end
    end
end
