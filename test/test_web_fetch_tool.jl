using OpenContentBroker
using EasyContext
using ToolCallFormat

# Test WebFetchTool
wf = WebFetchTool()
call = ToolCallFormat.ParsedCall(name="web_fetch", kwargs=Dict(
    "url"    => ToolCallFormat.ParsedValue(value="https://julialang.org", raw="https://julialang.org"),
    "prompt" => ToolCallFormat.ParsedValue(value="What is Julia? One paragraph.", raw="What is Julia? One paragraph."),
))
tool = ToolCallFormat.create_tool(wf, call)
ToolCallFormat.execute(tool, EasyContext.SimpleContext())
println("=== WebFetchTool result ===")
println(ToolCallFormat.result2string(tool))
