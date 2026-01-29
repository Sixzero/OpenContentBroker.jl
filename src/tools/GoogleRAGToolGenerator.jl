using EasyContext: AbstractToolGenerator
using ToolCallFormat: ParsedCall, toolname, get_description, tool_format

export GoogleRAGToolGenerator

# Generator for custom adapter configuration (optional - uses default if not specified)
@kwdef struct GoogleRAGToolGenerator <: AbstractToolGenerator
    adapter::GoogleRAGAdapter = GoogleRAGAdapter()
end

# Generator creates tool instances - delegates to GoogleRAGTool
function EasyContext.create_tool(generator::GoogleRAGToolGenerator, call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    query = query_pv !== nothing ? query_pv.value : ""

    # Execute with custom adapter
    response = OpenCacheLayer.get_content(generator.adapter, query)
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

    # Return a GoogleRAGTool with pre-filled result
    tool = GoogleRAGTool(query=query)
    tool.result = "Google RAG Search results for '$query':\n$result"
    tool
end

EasyContext.toolname(::GoogleRAGToolGenerator) = "google_rag"
EasyContext.toolname(::Type{GoogleRAGToolGenerator}) = "google_rag"
EasyContext.get_description(::Type{GoogleRAGToolGenerator}) = ToolCallFormat.get_description(GoogleRAGTool)
EasyContext.tool_format(::Type{GoogleRAGToolGenerator}) = :single_line
EasyContext.tool_format(::GoogleRAGToolGenerator) = :single_line
