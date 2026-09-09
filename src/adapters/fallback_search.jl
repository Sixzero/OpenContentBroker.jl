using OpenCacheLayer

# TODO: evaluate Monid (https://monid.ai, launched 2026-08-27:
# https://x.com/shengkunye/status/2093050916953903451) as a free
# last-resort adapter in this chain (Serper -> Tavily -> Monid). Free
# search/fetch for agents on TinyFish infra, but 1 day old at time of
# writing, rate limits undocumented, needs an API key despite the "no key"
# marketing. Revisit ~2 weeks after launch; adapter is ~30 lines on the
# env_key_pool/try_keys pattern in search_base.jl.
@kwdef struct FallbackSearchAdapter <: AbstractSearchAdapter
    primary::AbstractSearchAdapter = SerpAdapter(engine="google")
    fallback::AbstractSearchAdapter = TavilyAdapter()
end

function OpenCacheLayer.get_content(adapter::FallbackSearchAdapter, query::String; kwargs...)
    primary_err = nothing
    results = try
        OpenCacheLayer.get_content(adapter.primary, query; kwargs...)
    catch e
        primary_err = e
        @warn "Primary search failed, falling back" exception=e
        SearchResult[]
    end
    isempty(results) || return results
    primary_err === nothing && @info "Primary search empty, using fallback"
    try
        OpenCacheLayer.get_content(adapter.fallback, query; kwargs...)
    catch e
        # Surface the primary failure too, otherwise a missing fallback key masks the real cause.
        primary_err === nothing && rethrow()
        error("Primary search failed: $(sprint(showerror, primary_err)); fallback failed: $(sprint(showerror, e))")
    end
end

OpenCacheLayer.get_adapter_hash(adapter::FallbackSearchAdapter) =
    "FB_$(get_adapter_hash(adapter.primary))_$(get_adapter_hash(adapter.fallback))"
