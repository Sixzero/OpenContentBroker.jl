# WebFetchTool - Fetch URL + summarize via LLM (like SummarizeTool but for URLs)
#
# Reuses WEB_CONTENT_ADAPTER (MarkdownifyAdapter) for fetching,
# sends content + prompt to haiku for focused extraction.

using EasyContext: AbstractToolGenerator, create_FluidAgent, NativeExtractor, work, LLM_safetorun
import ToolCallFormat
using ToolCallFormat: ParsedCall, AbstractContext, description_from_schema

export WebFetchTool

const WEB_FETCH_TAG = "web_fetch"

@kwdef mutable struct WebFetchToolCall <: EasyContext.AbstractTool
    _id::UUID = uuid4()
    url::String
    prompt::String
    model::Union{String, Nothing}
    stats::EasyContext.SubAgentStats = EasyContext.SubAgentStats()
    result::Union{String, Nothing} = nothing
end

ToolCallFormat.get_id(t::WebFetchToolCall) = t._id
EasyContext.LLM_safetorun(::WebFetchToolCall) = true

const WEB_FETCH_SYS_PROMPT = "You process web page content. Be concise, accurate, and focus on what the user asks. Output only the relevant information."

function ToolCallFormat.execute(cmd::WebFetchToolCall, ctx::AbstractContext)
    model = something(cmd.model, "anthropic:anthropic/claude-haiku-4.5")

    content_str = try
        content = OpenCacheLayer.get_content(get_web_content_adapter(), cmd.url)
        content.content
    catch e
        cmd.result = "Failed to fetch $(cmd.url): $(sprint(showerror, e))"
        return cmd
    end

    user_msg = """$(cmd.prompt)

URL: $(cmd.url)
Content:
$(content_str)"""

    agent = create_FluidAgent(model;
        tools = [],
        extractor_type = tools -> NativeExtractor(tools; no_confirm=true),
        sys_msg = WEB_FETCH_SYS_PROMPT,
    )


    response = work(agent, user_msg; io=devnull, quiet=true, on_meta_ai=EasyContext.on_meta_ai(cmd.stats))
    cmd.result = response !== nothing ? something(response.content, "(no response)") : "(no response)"
    cmd
end

ToolCallFormat.result2string(cmd::WebFetchToolCall) = something(cmd.result, "(no result)")

# --- Generator ---
@kwdef struct WebFetchTool <: AbstractToolGenerator
    model::Union{String, Nothing} = nothing
end

ToolCallFormat.toolname(::WebFetchTool) = WEB_FETCH_TAG
ToolCallFormat.toolname(::Type{WebFetchTool}) = WEB_FETCH_TAG
ToolCallFormat.toolname(::WebFetchToolCall) = WEB_FETCH_TAG
ToolCallFormat.toolname(::Type{WebFetchToolCall}) = WEB_FETCH_TAG

const WEB_FETCH_SCHEMA = (
    name = WEB_FETCH_TAG,
    description = "Fetch a URL and extract information based on a prompt. Returns a focused summary of the web page content.",
    params = [
        (name = "url",    type = "string", description = "The URL to fetch", required = true),
        (name = "prompt", type = "string", description = "What information to extract from the page", required = true),
    ]
)

ToolCallFormat.get_tool_schema(::WebFetchTool) = WEB_FETCH_SCHEMA
ToolCallFormat.get_tool_schema(::Type{WebFetchToolCall}) = WEB_FETCH_SCHEMA
ToolCallFormat.get_description(::WebFetchTool) = description_from_schema(WEB_FETCH_SCHEMA)

function ToolCallFormat.create_tool(wf::WebFetchTool, call::ParsedCall)
    url_pv = get(call.kwargs, "url", nothing)
    url = url_pv !== nothing ? url_pv.value : ""
    prompt_pv = get(call.kwargs, "prompt", nothing)
    prompt = prompt_pv !== nothing ? prompt_pv.value : "Summarize this page."
    WebFetchToolCall(; url, prompt, model=wf.model)
end

# Type-based create_tool for recreate_tool registry path
function ToolCallFormat.create_tool(::Type{WebFetchToolCall}, call::ParsedCall; extra_kwargs...)
    url_pv = get(call.kwargs, "url", nothing)
    url = url_pv !== nothing ? url_pv.value : ""
    prompt_pv = get(call.kwargs, "prompt", nothing)
    prompt = prompt_pv !== nothing ? prompt_pv.value : "Summarize this page."
    WebFetchToolCall(; url, prompt, model=nothing)
end
