using HTTP
using JSON3
using URIs
using Dates
using OpenCacheLayer

struct DDGAdapter <: OpenCacheLayer.ChatsLikeAdapter
    region::String
end

DDGAdapter() = DDGAdapter("wt-wt")  # worldwide

function OpenCacheLayer.get_content(adapter::DDGAdapter, query::String)
    response = HTTP.get(
        "https://api.duckduckgo.com/?q=$(URIs.escapeuri(query))&format=json&region=$(adapter.region)"
    )
    
    data = JSON3.read(response.body)
    results = SearchResult[]
    
    # Process abstract result if present
    if !isempty(data.Abstract)
        push!(results, SearchResult(
            data.Heading,
            data.AbstractURL,
            data.Abstract,
            1.0,
            now()
        ))
    end
    
    # Process related topics
    for topic in data.RelatedTopics
        haskey(topic, :FirstURL) || continue
        push!(results, SearchResult(
            get(topic, :Result, topic.Text),
            topic.FirstURL,
            topic.Text,
            0.8,
            now()
        ))
    end
    
    results
end

OpenCacheLayer.get_adapter_hash(::DDGAdapter) = "DDG_SEARCH"
