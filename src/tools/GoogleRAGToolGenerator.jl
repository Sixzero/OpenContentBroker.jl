using EasyContext: AbstractToolGenerator
import ToolCallFormat
using ToolCallFormat: ParsedCall, toolname, get_description, AbstractContext

export GoogleRAGToolGenerator

# Wrapper tool that holds a custom adapter (for lazy execution)
@kwdef mutable struct GoogleRAGToolWithAdapter <: EasyContext.AbstractTool
    _id::UUID = uuid4()
    adapter::GoogleRAGAdapter
    query::String
    result::String = ""
end

# Generator for custom adapter configuration (optional - uses default if not specified)
@kwdef struct GoogleRAGToolGenerator <: AbstractToolGenerator
    adapter::GoogleRAGAdapter = GoogleRAGAdapter()
end

# Generator creates tool instances - LAZY: just stores query, doesn't execute
function EasyContext.create_tool(generator::GoogleRAGToolGenerator, call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    query = query_pv !== nothing ? query_pv.value : ""

    # Return tool with adapter reference - execution happens in preprocess/execute
    GoogleRAGToolWithAdapter(adapter=generator.adapter, query=query)
end

# Execution happens here (called after permission check)
function ToolCallFormat.execute(tool::GoogleRAGToolWithAdapter, ctx::AbstractContext)
    response = OpenCacheLayer.get_content(tool.adapter, tool.query)
    results, elapsed, cost = response.results, response.elapsed, response.cost

    result = join([
        """
        # URL: $(string(r.url))
        $(r.content)
        """ for r in results], "\n\n")

    println("Google RAG Search results:")
    println(join(["URL: $(string(r.url))" for r in results], "\n"))
    if cost > 0
        println("Cost: \$$(round(cost, digits=4))")
    end

    tool.result = "Google RAG Search results for '$(tool.query)':\n$result"
end

ToolCallFormat.result2string(tool::GoogleRAGToolWithAdapter) = tool.result
ToolCallFormat.toolname(::GoogleRAGToolWithAdapter) = "google_rag"
ToolCallFormat.toolname(::Type{GoogleRAGToolWithAdapter}) = "google_rag"
ToolCallFormat.get_id(tool::GoogleRAGToolWithAdapter) = tool._id

EasyContext.toolname(::GoogleRAGToolGenerator) = "google_rag"
EasyContext.toolname(::Type{GoogleRAGToolGenerator}) = "google_rag"
EasyContext.get_description(::Type{GoogleRAGToolGenerator}) = get_description(GoogleRAGTool)
ToolCallFormat.get_tool_schema(::GoogleRAGToolGenerator) = ToolCallFormat.get_tool_schema(GoogleRAGTool)
