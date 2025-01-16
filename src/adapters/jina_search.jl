using HTTP
using JSON3
using Dates
using URIs
using OpenCacheLayer

@kwdef struct JinaAdapter <: OpenCacheLayer.ChatsLikeAdapter
    api_key::String = get(ENV, "JINA_API_KEY", "")
    retain_images::Bool = false
end

JinaAdapter(api_key::String) = JinaAdapter(api_key, false)

function OpenCacheLayer.get_content(adapter::JinaAdapter, query::String)
    headers = [
        "Authorization" => "Bearer $(adapter.api_key)",
        "Accept" => "application/json"
    ]
    
    if !adapter.retain_images
        push!(headers, "X-Retain-Images" => "none")
    end
    
    response = HTTP.get(
        "https://s.jina.ai/$(URIs.escapeuri(query))",
        headers
    )
    
    data = JSON3.read(response.body)
    timestamp = now()  # Single timestamp for all results
    
    [SearchResult(
        result.title,
        result.url,
        result.content,
        get(result, :score, 1.0),
        timestamp
    ) for result in data.data]
end

OpenCacheLayer.get_adapter_hash(adapter::JinaAdapter) = 
    "JINA_$(adapter.api_key[1:min(8,length(adapter.api_key))])"
