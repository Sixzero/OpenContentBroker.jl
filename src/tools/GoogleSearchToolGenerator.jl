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
    tools::Vector
    model::Union{String, Nothing}
end

ToolCallFormat.get_id(t::GoogleSearchToolCall) = t._id
EasyContext.LLM_safetorun(::GoogleSearchToolCall) = true

const _google_search_gen_results = Dict{UUID, String}()

const GOOGLE_SEARCH_GEN_SYS_PROMPT = """You are a web research agent. You receive Google search results and have a web_fetch tool to read pages.

Your task:
1. Review the search results below
2. Use web_fetch to read the most relevant URLs (2-3 max)
3. Synthesize the information into a clear, concise answer

Be direct and factual. Cite sources when possible."""

function ToolCallFormat.execute(cmd::GoogleSearchToolCall, ctx::AbstractContext)
    model = something(cmd.model, "anthropic:anthropic/claude-haiku-4.5")

    # Google search via existing adapter
    results = try
        OpenCacheLayer.get_content(GOOGLE_SEARCH_ADAPTER(), cmd.query)
    catch e
        _google_search_gen_results[cmd._id] = "Google search failed: $(sprint(showerror, e))"
        return cmd
    end

    if isempty(results)
        _google_search_gen_results[cmd._id] = "No search results for '$(cmd.query)'"
        return cmd
    end

    formatted = join(["$(i). $(r.title)\n   URL: $(r.url)\n   $(r.content)"
                      for (i,r) in enumerate(results)], "\n\n")

    user_msg = """Search query: "$(cmd.query)"

Search results:
$formatted

Fetch the most relevant URLs and synthesize an answer to the query."""

    agent = create_FluidAgent(model;
        tools = cmd.tools,
        extractor_type = tools -> NativeExtractor(tools; no_confirm=true),
        sys_msg = GOOGLE_SEARCH_GEN_SYS_PROMPT,
    )
    agent.tool_mode = :native

    response = work(agent, user_msg; io=devnull, quiet=true)
    content = response !== nothing ? something(response.content, "(no response)") : "(no response)"
    _google_search_gen_results[cmd._id] = content
    cmd
end

ToolCallFormat.result2string(cmd::GoogleSearchToolCall) = pop!(_google_search_gen_results, cmd._id, "(no result)")

# --- Generator ---
@kwdef struct GoogleSearchToolGenerator <: AbstractToolGenerator
    model::Union{String, Nothing} = nothing
end

ToolCallFormat.toolname(::GoogleSearchToolGenerator) = "google_search"

ToolCallFormat.get_description(::GoogleSearchToolGenerator) = ToolCallFormat.get_description(GoogleSearchTool)
ToolCallFormat.get_tool_schema(::GoogleSearchToolGenerator) = ToolCallFormat.get_tool_schema(GoogleSearchTool)

function ToolCallFormat.create_tool(gs::GoogleSearchToolGenerator, call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    query = query_pv !== nothing ? query_pv.value : ""
    tools = [WebFetchTool(model=gs.model)]
    GoogleSearchToolCall(; query, tools, model=gs.model)
end
