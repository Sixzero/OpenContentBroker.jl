using UUIDs
using OpenCacheLayer
using EasyContext: ToolTag, FileChunk, SourcePath
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


EasyContext.create_tool(::Type{GoogleRAGTool}, cmd::ToolTag) = GoogleRAGTool(; query=cmd.args)

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

EasyContext.toolname(::Type{GoogleRAGTool}) = "GOOGLE_RAG"
EasyContext.get_description(::Type{GoogleRAGTool}) = """
GoogleRAGTool for searching with Google and then reranking results with a RAG pipeline:
GOOGLE_RAG [your search query] [$STOP_SEQUENCE]

$STOP_SEQUENCE is optional, if provided the tool will be instantly executed.
Generally this is a better Google search, returning higher quality results.
"""
EasyContext.stop_sequence(::Type{GoogleRAGTool}) = STOP_SEQUENCE
EasyContext.result2string(tool::GoogleRAGTool)::String = 
    "Google RAG Search results for '$(tool.query)':\n$(tool.result)"
EasyContext.tool_format(::Type{GoogleRAGTool}) = :single_line

EasyContext.execute_required_tools(::GoogleRAGTool) = true