using OpenCacheLayer

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
