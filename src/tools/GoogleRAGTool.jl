using UUIDs
using OpenCacheLayer
using EasyContext: ToolTag
import EasyContext

@kwdef mutable struct GoogleRAGTool <: AbstractTool
    id::UUID = uuid4()
    adapter::GoogleRAGAdapter = GoogleRAGAdapter()
    query::String
    result::String = ""
end

GoogleRAGTool(cmd::ToolTag) = GoogleRAGTool(query=cmd.args)

function EasyContext.execute(tool::GoogleRAGTool; no_confirm=false)
    results = OpenCacheLayer.get_content(tool.adapter, tool.query)
    
    tool.result = join([
        """
        # URL: $(string(r.url))
        $(r.content)
        """ for r in results], "\n\n")
    
    println("Google RAG Search results:")
    println(join(["URL: $(string(r.url))" for r in results], "\n"))
end

EasyContext.instantiate(::Val{:GOOGLE_RAG}, cmd::ToolTag) = GoogleRAGTool(cmd)
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
