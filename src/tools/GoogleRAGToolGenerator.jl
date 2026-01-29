using UUIDs
using EasyContext: AbstractToolGenerator
using ToolCallFormat: ParsedCall
using OpenContentBroker

export GoogleRAGToolGenerator

@kwdef struct GoogleRAGToolGenerator <: AbstractToolGenerator
    adapter::GoogleRAGAdapter = GoogleRAGAdapter()
end

function EasyContext.create_tool(generator::GoogleRAGToolGenerator, call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    GoogleRAGTool(; adapter=generator.adapter, query=query_pv !== nothing ? query_pv.value : "")
end

EasyContext.toolname(::GoogleRAGToolGenerator) = "google_rag"
EasyContext.toolname(::Type{GoogleRAGToolGenerator}) = "google_rag"
EasyContext.get_description(::Type{GoogleRAGToolGenerator}) = EasyContext.get_description(GoogleRAGTool)
EasyContext.tool_format(::Type{GoogleRAGToolGenerator}) = EasyContext.tool_format(GoogleRAGTool)
EasyContext.tool_format(::GoogleRAGToolGenerator) = EasyContext.tool_format(GoogleRAGTool)
