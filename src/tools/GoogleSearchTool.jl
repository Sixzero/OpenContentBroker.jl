using UUIDs
using OpenCacheLayer
using EasyContext: ToolTag
import EasyContext

@kwdef mutable struct GoogleSearchTool <: AbstractTool
    id::UUID = uuid4()
    adapter::GoogleAdapter = GoogleAdapter()
    query::String
    result::String = ""
end

EasyContext.create_tool(::Type{GoogleSearchTool}, cmd::ToolTag) = GoogleSearchTool(query=cmd.args)

EasyContext.toolname(::Type{GoogleSearchTool}) = "GOOGLE_SEARCH"
EasyContext.get_description(::Type{GoogleSearchTool}) = """
GoogleSearchTool for searching with Google:
GOOGLE_SEARCH [your search query] [$STOP_SEQUENCE]

$STOP_SEQUENCE is optional, if provided the tool will be instantly executed.
"""
EasyContext.stop_sequence(::Type{GoogleSearchTool}) = STOP_SEQUENCE

function EasyContext.execute(tool::GoogleSearchTool; no_confirm=false)
    results = OpenCacheLayer.get_content(tool.adapter, tool.query)
    formatted = join(["$(i). $(r.title)\n   $(r.url)\n   $(r.content)\n" 
                     for (i,r) in enumerate(results)], "\n")
    println("Google Search results:")
    for (i,r) in enumerate(results)
        println("$(i). $(r.title)\n   $(r.url)\n   $(r.content)\n")
    end
    tool.result = "$formatted"

end

EasyContext.result2string(tool::GoogleSearchTool)::String = "Search results for '$(tool.query)':\n\n$(tool.result)"
EasyContext.tool_format(::Type{GoogleSearchTool}) = :single_line

EasyContext.execute_required_tools(::GoogleSearchTool) = true
