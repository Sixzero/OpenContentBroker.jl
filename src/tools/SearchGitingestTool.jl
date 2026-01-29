using EasyContext
using EasyContext: search, parse_code_block, NewlineChunker, SourcePath

@kwdef struct GitChunk <: EasyContext.AbstractChunk
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

# Module-level pipeline
const SEARCH_GITINGEST_PIPELINE = EFFICIENT_PIPELINE()

function search_repos(query::String, urls::Vector{String}, repos::Vector{GitRepo})
    all_results = GitSearchResult[]
    chunker = NewlineChunker{GitChunk}(max_tokens=8000)

    for (url, repo) in zip(urls, repos)
        repo_path = replace(url, "https://github.com/" => "")
        contents = [f.content for f in repo.files]
        sources = ["$repo_path/$(f.path)" for f in repo.files]

        chunks = RAG.get_chunks(chunker, contents; sources=sources)
        chunk_strs = string.(chunks)

        selected_chunks = search(SEARCH_GITINGEST_PIPELINE, chunk_strs, query)

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

using ToolCallFormat: @deftool, CodeBlock

@deftool "Search in the codebase of GitHub repositories" function search_gitingest(
    query::String => "Search query",
    urls::CodeBlock => "GitHub repository URLs, one per line"
)
    # Parse the code block to extract just the URLs
    _, content = parse_code_block(string(urls))
    url_list = filter(!isempty, strip.(split(content, '\n')))

    repos = [ingest_repo(url) for url in url_list]
    results = search_repos(query, url_list, repos)

    println("\nMatched files:")
    for r in results
        println("\e[34mhttps://github.com/$(string(r.source))\e[0m")
    end

    "Search results for '$query' across $(length(url_list)) repositories:\n\n$(format_search_results(results))"
end
