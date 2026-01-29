using UUIDs
using PyCall

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

"Extract code context from GitHub repositories"
@deftool GitingestTool gitingest(url::String) = begin
    repo = ingest_repo(url)
    "Gitingest results for '$url':\n\n$(format_repo(repo))"
end
