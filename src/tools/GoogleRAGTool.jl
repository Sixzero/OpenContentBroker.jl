using UUIDs
using OpenCacheLayer
using ToolCallFormat: ParsedCall
using EasyContext: FileChunk, SourcePath
import EasyContext

@kwdef struct GoogleRAGToolResult
    results::Vector{GoogleRAGResult}
    query::String
    elapsed::Float64 = 0.0
    cost::Float64 = 0.0
end

@kwdef mutable struct GoogleRAGTool <: AbstractTool
    id::UUID = uuid4()
    adapter::GoogleRAGAdapter = GoogleRAGAdapter()
    query::String
    result::String = ""
    structured_result::Union{GoogleRAGToolResult, Nothing} = nothing
end


function EasyContext.create_tool(::Type{GoogleRAGTool}, call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    GoogleRAGTool(; query=query_pv !== nothing ? query_pv.value : "")
end

function EasyContext.execute(tool::GoogleRAGTool; no_confirm=false)
    response = OpenCacheLayer.get_content(tool.adapter, tool.query)
    
        results, elapsed, cost = response.results, response.elapsed, response.cost
        tool.structured_result = GoogleRAGToolResult(results, tool.query, elapsed, cost)

    tool.result = join([
        """
        # URL: $(string(r.url))
        $(r.content)
        """ for r in results], "\n\n")
    
    println("Google RAG Search results:")
    println(join(["URL: $(string(r.url))" for r in results], "\n"))
    if !isnothing(tool.structured_result) && tool.structured_result.cost > 0
        println("Cost: \$$(round(tool.structured_result.cost, digits=4))")
    end
end

EasyContext.toolname(::Type{GoogleRAGTool}) = "google_rag"
const GOOGLE_RAG_SCHEMA = (
    name = "google_rag",
    description = "Search with Google and rerank results with RAG pipeline for higher quality results",
    params = [(name = "query", type = "string", description = "Search query", required = true)]
)
EasyContext.get_tool_schema(::Type{GoogleRAGTool}) = GOOGLE_RAG_SCHEMA
EasyContext.get_description(::Type{GoogleRAGTool}) = EasyContext.description_from_schema(GOOGLE_RAG_SCHEMA)
EasyContext.result2string(tool::GoogleRAGTool)::String = 
    "Google RAG Search results for '$(tool.query)':\n$(tool.result)"
EasyContext.tool_format(::Type{GoogleRAGTool}) = :single_line

EasyContext.execute_required_tools(::GoogleRAGTool) = true