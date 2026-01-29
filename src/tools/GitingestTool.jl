using UUIDs
using PyCall
using ToolCallFormat: ParsedCall
using EasyContext: AbstractTool
import EasyContext

# Lazy load Python gitingest module
const gitingest = PyNULL()

function ensure_gitingest()
    if ispynull(gitingest)
        copy!(gitingest, pyimport("gitingest"))
    end
    gitingest
end

# Immutable data structures
struct GitFile
    path::String
    content::String
    size::Int
end

struct GitRepo
    summary::String
    tree::String
    files::Vector{GitFile}
end

@kwdef mutable struct GitingestTool <: AbstractTool
    id::UUID = uuid4()
    path::String
    repo::Union{Nothing,GitRepo} = nothing
    result::String = ""
end

# Core functionality
parse_file(path::AbstractString, content::Vector{String}) = 
    GitFile(path, join(content, "\n"), sum(length, content))

function parse_content(content::String)
    files = GitFile[]
    current_file = nothing
    current_content = String[]
    
    for line in split(content, '\n')
        if startswith(line, "File: ")
            if !isnothing(current_file)
                push!(files, parse_file(current_file, current_content))
            end
            current_file = strip(replace(line, "File: " => ""))
            empty!(current_content)
        else
            !isnothing(current_file) && push!(current_content, line)
        end
    end
    
    !isnothing(current_file) && push!(files, parse_file(current_file, current_content))
    files
end

ingest_repo(url::String) = 
    let gi = ensure_gitingest()
        @show url
        (summary, tree, content) = gi.ingest(url)
        GitRepo(summary, tree, parse_content(content))
    end

format_repo(repo::GitRepo) = """
## Summary

$(repo.summary)

## Directory Structure

$(repo.tree)

## Files ($(length(repo.files)))

$(join(["### $(f.path) ($(f.size) bytes)\n```\n$(f.content)\n```" for f in repo.files], "\n\n"))
"""

# Tool interface
function EasyContext.create_tool(::Type{GitingestTool}, call::ParsedCall)
    url_pv = get(call.kwargs, "url", nothing)
    GitingestTool(path=url_pv !== nothing ? url_pv.value : "")
end

EasyContext.toolname(::Type{GitingestTool}) = "gitingest"
const GITINGEST_SCHEMA = (
    name = "gitingest",
    description = "Extract code context from GitHub repositories",
    params = [(name = "url", type = "string", description = "GitHub repository URL", required = true)]
)
EasyContext.get_tool_schema(::Type{GitingestTool}) = GITINGEST_SCHEMA
EasyContext.get_description(::Type{GitingestTool}) = EasyContext.description_from_schema(GITINGEST_SCHEMA)

function EasyContext.execute(tool::GitingestTool; no_confirm=false)
    tool.repo = ingest_repo(tool.path)
    tool.result = format_repo(tool.repo)
end

EasyContext.result2string(tool::GitingestTool)::String = 
    "Gitingest results for '$(tool.path)':\n\n$(tool.result)"
EasyContext.tool_format(::Type{GitingestTool}) = :single_line

EasyContext.execute_required_tools(::GitingestTool) = true