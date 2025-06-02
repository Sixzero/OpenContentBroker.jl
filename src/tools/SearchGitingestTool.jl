using UUIDs
using EasyContext: ToolTag, search, parse_code_block
import EasyContext
using EasyContext: NewlineChunker, SourcePath

@kwdef struct GitChunk <: RAG.AbstractChunk
    source::SourcePath
    content::String = ""
end

function RAG.load_text(::Type{GitChunk}, content::AbstractString; source)
    content, source
end

function RAG.load_text(::Type{GitChunk}, file::GitFile; source=file.path)
    file.content, source
end

@kwdef struct GitSearchResult
    source::SourcePath
    chunk::String
    score::Float64
end

@kwdef mutable struct SearchGitingestTool <: AbstractTool
    id::UUID = uuid4()
    query::String
    urls::Vector{String}
    repos::Vector{GitRepo} = GitRepo[]
    results::Vector{GitSearchResult} = GitSearchResult[]
    result::String = ""
    rag_pipeline::Any = EFFICIENT_PIPELINE()
end
EasyContext.create_tool(::Type{SearchGitingestTool}, cmd::ToolTag) = let query = strip(cmd.args)
    # Parse the code block to extract just the URLs
    _, content = parse_code_block(cmd.content) # this unwraps content from ```urls content ``` block
    urls = filter(!isempty, strip.(split(content, '\n')))
    SearchGitingestTool(query=query, urls=urls)
end

function search_repos(tool::SearchGitingestTool)
    all_results = GitSearchResult[]
    chunker = NewlineChunker{GitChunk}(max_tokens=8000)
    
    for (url, repo) in zip(tool.urls, tool.repos)
        # Extract repo owner and name from URL
        repo_path = replace(url, "https://github.com/" => "")
        
        contents = [f.content for f in repo.files]
        # Prefix file paths with repo path
        sources = ["$repo_path/$(f.path)" for f in repo.files]
        
        chunks = RAG.get_chunks(chunker, contents; sources=sources)
        chunk_strs = string.(chunks)
        
        # Get selected chunks from search
        selected_chunks = search(tool.rag_pipeline, chunk_strs, tool.query)
        
        # Find indices of selected chunks in original chunks
        for chunk in selected_chunks
            if (idx = findfirst(==(chunk), chunk_strs)) !== nothing
                push!(all_results, GitSearchResult(
                    source=chunks[idx].source,
                    chunk=chunks[idx].content,
                    score=1.0
                ))
            end
        end
    end
    all_results
end

format_search_results(results::Vector{GitSearchResult}) = join([
    """
    File: $(string(r.source))
    $(r.chunk)
    """ for r in results], "\n\n")


EasyContext.toolname(::Type{SearchGitingestTool}) = "SEARCH_GITINGEST"
EasyContext.get_description(::Type{SearchGitingestTool}) = """
SearchGitingestTool for searching in the codebase of github repositories:
SEARCH_GITINGEST search_query
```urls
repo_paths
```

Example: 
SEARCH_GITINGEST "Where is the main function?"
```urls
https://github.com/user1/repoX
https://github.com/user2/repoY
```

You always need to list the urls in which we want to search. 
$STOP_SEQUENCE is optional, if provided the tool will be instantly executed.
"""
EasyContext.stop_sequence(::Type{SearchGitingestTool}) = STOP_SEQUENCE

function EasyContext.execute(tool::SearchGitingestTool; no_confirm=false)
    tool.repos = [ingest_repo(url) for url in tool.urls]
    tool.results = search_repos(tool)
    tool.result = format_search_results(tool.results)
    println("\nMatched files:")
    for r in tool.results
        println("\e[34mhttps://github.com/$(string(r.source))\e[0m")
    end
end

EasyContext.result2string(tool::SearchGitingestTool)::String = 
    "Search results for '$(tool.query)' across $(length(tool.urls)) repositories:\n\n$(tool.result)"
EasyContext.tool_format(::Type{SearchGitingestTool}) = :multi_line
