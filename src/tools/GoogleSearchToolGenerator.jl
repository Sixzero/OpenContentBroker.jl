# GoogleSearchToolGenerator - Map-reduce web search via sub-agent
#
# Google search → spawn sub-agent with WebFetchTool → agent fetches
# relevant URLs and synthesizes answer.

using EasyContext: AbstractToolGenerator, create_FluidAgent, NativeExtractor, work, LLM_safetorun
import ToolCallFormat
using ToolCallFormat: ParsedCall, AbstractContext

export GoogleSearchToolGenerator

@kwdef mutable struct GoogleSearchToolCall <: EasyContext.AbstractTool
    _id::UUID = uuid4()
    query::String
    prompt::String = ""
    tools::Vector
    model::Union{String, Nothing}
    stats::EasyContext.SubAgentStats = EasyContext.SubAgentStats()
    result::Union{String, Nothing} = nothing
end

ToolCallFormat.get_id(t::GoogleSearchToolCall) = t._id
EasyContext.LLM_safetorun(::GoogleSearchToolCall) = true

const GOOGLE_SEARCH_GEN_SYS_PROMPT = """You are a web research agent. You receive Google search results and have a web_fetch tool to read pages.

Your task:
1. Review the search results below
2. Use web_fetch to read the most relevant URLs (2-3 max)
3. Synthesize the information into a clear, concise answer

IMPORTANT: Always cite your sources. At the end of your answer, include a "Sources:" section listing the URLs you used."""

function ToolCallFormat.execute(cmd::GoogleSearchToolCall, ctx::AbstractContext)
    model = something(cmd.model, "anthropic:anthropic/claude-haiku-4.5")

    # Google search via existing adapter
    results = try
        OpenCacheLayer.get_content(GOOGLE_SEARCH_ADAPTER(), cmd.query)
    catch e
        cmd.result = "Google search failed: $(sprint(showerror, e))"
        return cmd
    end

    if isempty(results)
        cmd.result = "No search results for '$(cmd.query)'"
        return cmd
    end

    formatted = join(["$(i). $(r.title)\n   URL: $(r.url)\n   $(r.content)"
                      for (i,r) in enumerate(results)], "\n\n")

    focus = isempty(cmd.prompt) ? "Fetch the most relevant URLs and synthesize an answer to the query." : cmd.prompt

    user_msg = """Search query: "$(cmd.query)"

Search results:
$formatted

$focus"""

    agent = create_FluidAgent(model;
        tools = cmd.tools,
        extractor_type = tools -> NativeExtractor(tools; no_confirm=true),
        sys_msg = GOOGLE_SEARCH_GEN_SYS_PROMPT,
    )


    response = work(agent, user_msg; io=devnull, quiet=true, on_meta_ai=EasyContext.on_meta_ai(cmd.stats))
    cmd.result = response !== nothing ? something(response.content, "(no response)") : "(no response)"
    cmd
end

ToolCallFormat.result2string(cmd::GoogleSearchToolCall) = something(cmd.result, "(no result)")

# --- Generator ---
@kwdef struct GoogleSearchToolGenerator <: AbstractToolGenerator
    model::Union{String, Nothing} = nothing
end

ToolCallFormat.toolname(::GoogleSearchToolGenerator) = "google_search"
ToolCallFormat.toolname(::Type{GoogleSearchToolGenerator}) = "google_search"
ToolCallFormat.toolname(::GoogleSearchToolCall) = "google_search"
ToolCallFormat.toolname(::Type{GoogleSearchToolCall}) = "google_search"

ToolCallFormat.get_description(::GoogleSearchToolGenerator) = ToolCallFormat.get_description(GoogleSearchTool)
ToolCallFormat.get_tool_schema(::GoogleSearchToolGenerator) = ToolCallFormat.get_tool_schema(GoogleSearchTool)
ToolCallFormat.get_tool_schema(::Type{GoogleSearchToolCall}) = ToolCallFormat.get_tool_schema(GoogleSearchTool)

function ToolCallFormat.create_tool(gs::GoogleSearchToolGenerator, call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    query = query_pv !== nothing ? query_pv.value : ""
    prompt_pv = get(call.kwargs, "prompt", nothing)
    prompt = prompt_pv !== nothing ? prompt_pv.value : ""
    tools = [WebFetchTool(model=gs.model)]
    GoogleSearchToolCall(; query, prompt, tools, model=gs.model)
end

# Type-based create_tool for recreate_tool registry path
function ToolCallFormat.create_tool(::Type{GoogleSearchToolCall}, call::ParsedCall; extra_kwargs...)
    query_pv = get(call.kwargs, "query", nothing)
    query = query_pv !== nothing ? query_pv.value : ""
    prompt_pv = get(call.kwargs, "prompt", nothing)
    prompt = prompt_pv !== nothing ? prompt_pv.value : ""
    tools = [WebFetchTool()]
    GoogleSearchToolCall(; query, prompt, tools, model=nothing)
end
