using OpenContentBroker
using EasyContext: execute, result2string

# Create a GoogleSearchTool instance with a search query
tool = GoogleSearchTool(query="gitingest usage")
tool = GoogleSearchTool(query="gitingest api usage")

# Execute the search
execute(tool)

# Print the results
println(result2string(tool))
