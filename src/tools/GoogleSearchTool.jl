using UUIDs
using OpenCacheLayer
using ToolCallFormat: ParsedCall
import EasyContext

@kwdef mutable struct GoogleSearchTool <: AbstractTool
    id::UUID = uuid4()
    adapter::GoogleAdapter = GoogleAdapter()
    query::String
    result::String = ""
end

function EasyContext.create_tool(::Type{GoogleSearchTool}, call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    GoogleSearchTool(query=query_pv !== nothing ? query_pv.value : "")
end

EasyContext.toolname(::Type{GoogleSearchTool}) = "google_search"
const GOOGLE_SEARCH_SCHEMA = (
    name = "google_search",
    description = "Search with Google",
    params = [(name = "query", type = "string", description = "Search query", required = true)]
)
EasyContext.get_tool_schema(::Type{GoogleSearchTool}) = GOOGLE_SEARCH_SCHEMA
EasyContext.get_description(::Type{GoogleSearchTool}) = EasyContext.description_from_schema(GOOGLE_SEARCH_SCHEMA)

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
