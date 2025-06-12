using EasyContext: AbstractChunker, AbstractChunk, SourcePath
using EasyContext: NewlineChunker

export HtmlChunker, HtmlChunk

struct HtmlChunk <: AbstractChunk
    source::String
    content::AbstractString
end
HtmlChunk(;source::SourcePath, content::AbstractString="") = HtmlChunk(string(source), content)

@kwdef struct HtmlChunker <: AbstractChunker
    chunker::NewlineChunker{HtmlChunk} = NewlineChunker{HtmlChunk}()
end

# Delegate core functionality to GeneralChunker
function RAG.get_chunks(chunker::HtmlChunker, text::AbstractString; source::AbstractString, kwargs...)
    chunks = [text]
    sources = [source]
    RAG.get_chunks(chunker.chunker, chunks; sources, kwargs...)
end

RAG.get_chunks(chunker::HtmlChunker, chunks::Vector{AbstractString}; sources, kwargs...) = 
    RAG.get_chunks(chunker.chunker, chunks; sources, kwargs...)

# Specialized HTML loading
function RAG.load_text(chunker::Type{HtmlChunk}, input::AbstractString;
                    source::AbstractString = input, kwargs...)
    content = input
    return content, source
end
