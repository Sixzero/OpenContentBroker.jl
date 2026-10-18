# GoogleSearchToolGenerator - plain Google search (no sub-agent).
#
# Returns titles/URLs/snippets; the calling agent decides whether to webfetch.
# Kept as a generator (vs. the @deftool GoogleSearchTool) for the on_results hook.

using EasyContext: AbstractToolGenerator, LLM_safetorun
import ToolCallFormat
using ToolCallFormat: ParsedCall, AbstractContext, ProcessResult

export GoogleSearchToolGenerator

@kwdef mutable struct GoogleSearchToolCall <: EasyContext.AbstractTool
    _id::UUID = uuid4()
    query::String
    # Kept empty for hosts that read sub-agent stats (no LLM calls anymore).
    stats::EasyContext.SubAgentStats = EasyContext.SubAgentStats()
    process_result::Union{ProcessResult, Nothing} = nothing
    _tool_call_id::Union{String, Nothing} = nothing
    # Called with the raw search results as soon as they arrive (e.g. push sources to a UI).
    on_results::Union{Function, Nothing} = nothing
end

ToolCallFormat.get_id(t::GoogleSearchToolCall) = t._id
EasyContext.LLM_safetorun(::GoogleSearchToolCall) = true

function ToolCallFormat.execute(cmd::GoogleSearchToolCall, ctx::AbstractContext)
    results = try
        OpenCacheLayer.get_content(GOOGLE_SEARCH_ADAPTER(), cmd.query)
    catch e
        cmd.process_result = ProcessResult("Google search failed: $(sprint(showerror, e))", 1)
        return cmd
    end

    if isempty(results)
        cmd.process_result = ProcessResult("No search results for '$(cmd.query)'", 1)
        return cmd
    end

    if cmd.on_results !== nothing
        try cmd.on_results(results) catch e @warn "google_search on_results hook failed" exception=e end
    end

    cmd.process_result = ProcessResult(format_search_results(cmd.query, results))
    cmd
end

# --- Generator ---
struct GoogleSearchToolGenerator <: AbstractToolGenerator end

ToolCallFormat.toolname(::GoogleSearchToolGenerator) = "google_search"
ToolCallFormat.toolname(::Type{GoogleSearchToolGenerator}) = "google_search"
ToolCallFormat.toolname(::GoogleSearchToolCall) = "google_search"
ToolCallFormat.toolname(::Type{GoogleSearchToolCall}) = "google_search"

ToolCallFormat.get_description(::GoogleSearchToolGenerator) = ToolCallFormat.get_description(GoogleSearchTool)
ToolCallFormat.get_tool_schema(::GoogleSearchToolGenerator) = ToolCallFormat.get_tool_schema(GoogleSearchTool)
ToolCallFormat.get_tool_schema(::Type{GoogleSearchToolCall}) = ToolCallFormat.get_tool_schema(GoogleSearchTool)

function _google_search_call(call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    GoogleSearchToolCall(; query = query_pv !== nothing ? query_pv.value : "")
end

ToolCallFormat.create_tool(::GoogleSearchToolGenerator, call::ParsedCall) = _google_search_call(call)
# Type-based create_tool for recreate_tool registry path
ToolCallFormat.create_tool(::Type{GoogleSearchToolCall}, call::ParsedCall; extra_kwargs...) = _google_search_call(call)
