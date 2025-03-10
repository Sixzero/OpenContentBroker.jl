using UUIDs
using OpenCacheLayer
using EasyContext: ToolTag
import EasyContext


@kwdef mutable struct WebSearchRerankerTool <: AbstractTool
    id::UUID = uuid4()
    query::String
    google_adapter::GoogleAdapter = GoogleAdapter()
    web_adapter::AbstractUrl2LLMAdapter = DictCacheLayer(FirecrawlAdapter())
    chunker::HtmlChunker = HtmlChunker()
    rag_pipeline::Any = EFFICIENT_PIPELINE()
    results::Vector{SearchResult} = SearchResult[]
    result::String = ""
end

WebSearchRerankerTool(cmd::ToolTag) = WebSearchRerankerTool(query=cmd.args)

function EasyContext.execute(tool::WebSearchRerankerTool; no_confirm=false)
    # Get Google results
    google_results = OpenCacheLayer.get_content(tool.google_adapter, tool.query)
    
    # Scrape and chunk each URL
    contents = String[]
    urls = String[]
    for result in google_results
        content = OpenCacheLayer.get_content(tool.web_adapter, result.url)
        push!(contents, content.content)
        push!(urls, result.url)
    end
    
    # Get chunks using RAG interface
    all_chunks = RAG.get_chunks(tool.chunker, contents; sources=urls)
    
    # Search through chunks
    chunk_texts = [get_content(c) for c in all_chunks]
    search_results = search(tool.rag_pipeline, chunk_texts, tool.query)
    
    # Format results
    tool.results = [SearchResult(
        url=get_source(res),
        content=get_content(res),
        score=score
    ) for res in search_results]
    
    tool.result = join([
        """
        URL: $(r.url) (score: $(round(r.score, digits=3)))
        $(r.content)
        """ for r in tool.results], "\n\n")
end

EasyContext.instantiate(::Val{:WEB_SEARCH_RERANK}, cmd::ToolTag) = WebSearchRerankerTool(cmd)
EasyContext.toolname(::Type{WebSearchRerankerTool}) = "WEB_SEARCH_RERANK"
EasyContext.get_description(::Type{WebSearchRerankerTool}) = """
WebSearchRerankerTool for searching and reranking web content:
WEB_SEARCH_RERANK search_query [$STOP_SEQUENCE]

$STOP_SEQUENCE is optional, if provided the tool will be instantly executed.
"""
EasyContext.stop_sequence(::Type{WebSearchRerankerTool}) = STOP_SEQUENCE
EasyContext.result2string(tool::WebSearchRerankerTool)::String = 
    "Reranked search results for '$(tool.query)':\n\n$(tool.result)"
EasyContext.tool_format(::Type{WebSearchRerankerTool}) = :single_line
