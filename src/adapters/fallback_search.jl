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
    results = try
        OpenCacheLayer.get_content(adapter.primary, query; kwargs...)
    catch e
        @warn "Primary search failed, falling back" exception=e
        SearchResult[]
    end
    if isempty(results)
        @info "Primary search empty, using fallback"
        return OpenCacheLayer.get_content(adapter.fallback, query; kwargs...)
    end
    results
end

OpenCacheLayer.get_adapter_hash(adapter::FallbackSearchAdapter) =
    "FB_$(get_adapter_hash(adapter.primary))_$(get_adapter_hash(adapter.fallback))"
