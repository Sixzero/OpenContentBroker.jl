using HTTP
using JSON3
using Dates
using OpenCacheLayer

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

@kwdef struct SerpAdapter <: AbstractSearchAdapter
    api_keys::Vector{String} = env_key_pool("SERP_API_KEY")
    engine::String = "google"  # Can be: google, bing, baidu, yandex, yahoo
end

function OpenCacheLayer.get_content(adapter::SerpAdapter, query::String; num::Int=10)
    isempty(adapter.api_keys) && error("No SERP_API_KEY configured")
    body = JSON3.write(Dict("q" => query, "num" => num))

    response = nothing
    for (i, key) in enumerate(adapter.api_keys)
        try
            response = HTTP.post(
                "https://google.serper.dev/search?engine=$(adapter.engine)",
                ["X-API-KEY" => key, "Content-Type" => "application/json"],
                body
            )
            break
        catch e
            i == length(adapter.api_keys) && rethrow()
            @warn "SERP key $i failed, trying next" exception=e
        end
    end

    data = JSON3.read(response.body)
    results = SearchResult[]
    timestamp = now()  # Single timestamp for all results

    # Process organic results
    for result in data.organic
        push!(results, SearchResult(
            get(result, :title, ""),
            result.link,
            get(result, :snippet, ""),
            1 / get(result, :position, 1.0),
            timestamp
        ))
    end

    results
end

# Key-independent: rotating keys must not invalidate the cache.
OpenCacheLayer.get_adapter_hash(adapter::SerpAdapter) = "SERP_$(adapter.engine)"
