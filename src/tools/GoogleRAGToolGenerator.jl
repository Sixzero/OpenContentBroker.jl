using UUIDs
using EasyContext: AbstractToolGenerator, ToolTag
using OpenContentBroker

export GoogleRAGToolGenerator

@kwdef struct GoogleRAGToolGenerator <: AbstractToolGenerator
    adapter::GoogleRAGAdapter = GoogleRAGAdapter()
end

function EasyContext.create_tool(generator::GoogleRAGToolGenerator, cmd::ToolTag)
    GoogleRAGTool(; adapter=generator.adapter, query=cmd.args)
end

EasyContext.toolname(::GoogleRAGToolGenerator) = "GOOGLE_RAG"
EasyContext.toolname(::Type{GoogleRAGToolGenerator}) = "GOOGLE_RAG"
EasyContext.get_description(::Type{GoogleRAGToolGenerator}) = EasyContext.get_description(GoogleRAGTool)
EasyContext.stop_sequence(::GoogleRAGToolGenerator) = EasyContext.stop_sequence(GoogleRAGTool)
EasyContext.stop_sequence(::Type{GoogleRAGToolGenerator}) = EasyContext.stop_sequence(GoogleRAGTool)
EasyContext.tool_format(::Type{GoogleRAGToolGenerator}) = EasyContext.tool_format(GoogleRAGTool)
EasyContext.tool_format(::GoogleRAGToolGenerator) = EasyContext.tool_format(GoogleRAGTool)
│    