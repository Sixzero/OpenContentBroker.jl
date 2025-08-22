using UUIDs
using OpenCacheLayer
using EasyContext
using EasyContext: ToolTag
import EasyContext

@kwdef mutable struct WebContentTool <: AbstractTool
    id::UUID = uuid4()
    adapter::DictCacheLayer{<:AbstractUrl2LLMAdapter} = DictCacheLayer(MarkdownifyAdapter())  # Changed to DictCacheLayer
    url::String
    result::String = ""
end

EasyContext.create_tool(::Type{WebContentTool}, cmd::ToolTag) = WebContentTool(url=cmd.args)
EasyContext.toolname(::Type{WebContentTool}) = "READ_URL"
EasyContext.get_description(::Type{WebContentTool}) = """
Extracts readable text content from a webpage:
READ_URL url [$STOP_SEQUENCE]

$STOP_SEQUENCE - optional, executes immediately
"""
EasyContext.stop_sequence(::Type{WebContentTool}) = STOP_SEQUENCE

function EasyContext.execute(tool::WebContentTool; no_confirm=false)
    content = OpenCacheLayer.get_content(tool.adapter, tool.url)
    tool.result = content.content
end

EasyContext.result2string(tool::WebContentTool)::String = "Content from '$(tool.url)':\n\n$(tool.result)"
EasyContext.tool_format(::Type{WebContentTool}) = :single_line

EasyContext.execute_required_tools(::WebContentTool) = true