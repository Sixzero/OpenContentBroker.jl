using UUIDs
using OpenCacheLayer
using EasyContext
using ToolCallFormat: ParsedCall
import EasyContext

@kwdef mutable struct WebContentTool <: AbstractTool
    id::UUID = uuid4()
    adapter::DictCacheLayer{<:AbstractUrl2LLMAdapter} = DictCacheLayer(MarkdownifyAdapter())  # Changed to DictCacheLayer
    url::String
    result::String = ""
end

function EasyContext.create_tool(::Type{WebContentTool}, call::ParsedCall)
    url_pv = get(call.kwargs, "url", nothing)
    WebContentTool(url=url_pv !== nothing ? url_pv.value : "")
end
EasyContext.toolname(::Type{WebContentTool}) = "read_url"

# Schema for description generation
const WEBCONTENT_SCHEMA = (
    name = "read_url",
    description = "Extracts readable text content from a webpage",
    params = [
        (name = "url", type = "string", description = "URL of the webpage to read", required = true),
    ]
)
EasyContext.get_tool_schema(::Type{WebContentTool}) = WEBCONTENT_SCHEMA
EasyContext.get_description(::Type{WebContentTool}) = EasyContext.description_from_schema(WEBCONTENT_SCHEMA)

function EasyContext.execute(tool::WebContentTool; no_confirm=false)
    content = OpenCacheLayer.get_content(tool.adapter, tool.url)
    tool.result = content.content
end

EasyContext.result2string(tool::WebContentTool)::String = "Content from '$(tool.url)':\n\n$(tool.result)"
EasyContext.tool_format(::Type{WebContentTool}) = :single_line

EasyContext.execute_required_tools(::WebContentTool) = true