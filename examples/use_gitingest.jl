using OpenContentBroker
using EasyContext: execute, result2string

# Create SearchGitingestTool instance with a search query and repo URL
tool = SearchGitingestTool(
    query="Where is the main function?",  # What we're looking for
    # query="How does https://github.com/cyclotruc/gitingest pulls down so fast all the file from a github, could you search for \"pulling downloading files from github\" or for soethign similar and tell me how this thing works?",  # What we're looking for
    # query="Which one is the largest file?",  # What we're looking for
    # urls=["https://github.com/SixZero/EasyContext.jl"]
    urls=["https://github.com/Sixzero/my-vike-vercel-test.git"]
    # urls=["https://github.com/cyclotruc/gitingest"]
)

# Execute the tool
# execute(tool)

tool = GitingestTool(path="https://github.com/Sixzero/my-vike-vercel-test.git")
execute(tool)
# Print results
println(result2string(tool))
