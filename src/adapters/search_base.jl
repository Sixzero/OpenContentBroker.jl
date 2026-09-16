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
# The response body is safe (never contains our key) and carries the provider's reason.
function error_brief(e::HTTP.StatusError)
    msg = try first(String(copy(e.response.body)), 200) catch; "" end
    isempty(msg) ? "HTTP $(e.status)" : "HTTP $(e.status): $msg"
end
error_brief(e::HTTP.RequestError) = "transport: $(typeof(e.error))"
error_brief(e) = string(typeof(e))

# Only errors caused by the *key* (invalid, out of credits, quota) should rotate to the next key.
# Serper answers 400 for both "Not enough credits" and bad requests ("Query too long"), so a
# 400 on a bad request would otherwise burn every key and get misreported as "all keys failed".
function is_key_error(e::HTTP.StatusError)
    e.status in (401, 402, 403, 429) && return true
    e.status == 400 && occursin(r"credit|quota|api.?key"i, error_brief(e))
end
is_key_error(e::HTTP.RequestError) = true
is_key_error(e) = true  # non-HTTP failures: keep the old rotate-then-fail behaviour

"""
Called as `f(name, err)` when every key of `name` failed (or none configured).
Hosts can set this to alert operators; default: no-op.
"""
const ON_KEYS_EXHAUSTED = Ref{Function}((name, err) -> nothing)

function keys_exhausted(name, err)
    try ON_KEYS_EXHAUSTED[](name, err) catch e; @warn "ON_KEYS_EXHAUSTED hook failed" error=error_brief(e) end
    # Detail (provider reason) goes to ops via the hook + log; the thrown message is what the
    # end user / agent sees — they can't fix our credits, so tell them what they *can* do.
    @error "$name exhausted" error=error_brief(err)
    error("web search is temporarily unavailable on our side (the team has been notified, error code SEARCH_QUOTA) — try again later or use webfetch on a known URL")
end

"""
Call `f(key)` with each key in turn, returning the first success. Transient
errors are retried once per key. Once every key failed, fires `ON_KEYS_EXHAUSTED`
and throws a sanitized ErrorException. Request errors (e.g. HTTP 400 "Query too long")
are not the key's fault: rethrown sanitized immediately, no rotation, no alert.
"""
function try_keys(f::Function, keys::Vector{String}, name::String; retries::Int=1)
    isempty(keys) && keys_exhausted(name, ErrorException("No $name configured"))
    for (i, key) in enumerate(keys)
        for attempt in 0:retries
            try
                return f(key)
            catch e
                e isa InterruptException && rethrow()
                is_key_error(e) || error("search provider rejected the request (error code SEARCH_BAD_REQUEST) — $(error_brief(e))")
                retry = attempt < retries && is_transient(e)
                retry || i < length(keys) || keys_exhausted(name, e)
                @warn "$name #$i failed, $(retry ? "retrying" : "trying next")" error=error_brief(e)
                retry || break
                sleep(0.5)
            end
        end
    end
end
