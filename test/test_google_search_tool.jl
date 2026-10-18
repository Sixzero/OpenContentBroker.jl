using OpenContentBroker
using EasyContext
using ToolCallFormat

# Test GoogleSearchToolGenerator (plain search, no sub-agent)
gs = GoogleSearchToolGenerator()
call = ToolCallFormat.ParsedCall(name="google_search", kwargs=Dict(
    "query" => ToolCallFormat.ParsedValue(value="Julia programming language async patterns", raw="Julia programming language async patterns"),
))
tool = ToolCallFormat.create_tool(gs, call)
ToolCallFormat.execute(tool, EasyContext.SimpleContext())
println("=== GoogleSearchToolGenerator result ===")
println(ToolCallFormat.result2string(tool))
