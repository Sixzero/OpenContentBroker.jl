using OpenCacheLayer: get_content
using ToolCallFormat: ParsedCall
using EasyContext: create_voyage_embedder, TwoLayerRAG, ReduceGPTReranker, TopK, BM25Embedder
import EasyContext

@kwdef mutable struct GmailSearchTool <: AbstractTool
    id::UUID = uuid4()
    query::String = ""
    rag_pipeline::AbstractRAGPipeline = EFFICIENT_PIPELINE()
    gmail_adapter::GmailAdapter = GmailAdapter()  # Uses ENV defaults
    emails::Vector{GmailMessage} = GmailMessage[]
    search_results::Vector{String} = String[]
    result_indices::Vector{Int} = Int[]  # Add indices tracking
end

function EasyContext.create_tool(::Type{GmailSearchTool}, call::ParsedCall)
    query_pv = get(call.kwargs, "query", nothing)
    GmailSearchTool(query=query_pv !== nothing ? query_pv.value : "")
end

function EasyContext.execute(tool::GmailSearchTool; 
    from::DateTime=now() - Day(7),
    max_results::Int=100,
    labels::Vector{String}=["INBOX"],
    no_confirm::Bool=false
)
    # Get emails
    tool.emails = get_content(tool.gmail_adapter; from, max_results, labels)
    
    # Skip if no emails found
    isempty(tool.emails) && return
    
    # Prepare email contents for reranking
    email_texts = [
        """
        Subject: $(email.subject)
        From: $(email.from)
        Date: $(email.date)
        
        $(email.body)
        """ for email in tool.emails
    ]
    
    println("Reranking $(length(email_texts)) emails...")
    # Search through emails using RAG pipeline and store results
    tool.search_results = search(tool.rag_pipeline, email_texts, tool.query)
    tool.result_indices = [findfirst(t -> occursin(r, t), email_texts) for r in tool.search_results]
    @info EasyContext.result2string(tool)
    tool.search_results
end

# Tool interface implementations
EasyContext.toolname(::Type{GmailSearchTool}) = "gmail_search"
const GMAIL_SEARCH_SCHEMA = (
    name = "gmail_search",
    description = "Search relevant emails for a query",
    params = [(name = "query", type = "string", description = "Search query", required = true)]
)
EasyContext.get_tool_schema(::Type{GmailSearchTool}) = GMAIL_SEARCH_SCHEMA
EasyContext.get_description(::Type{GmailSearchTool}) = EasyContext.description_from_schema(GMAIL_SEARCH_SCHEMA)
EasyContext.result2string(tool::GmailSearchTool)::String = 
    if isempty(tool.search_results) 
        "No emails found matching the criteria."
    else
        results = []
        for (chunk, idx) in zip(tool.search_results, tool.result_indices)
            email = tool.emails[idx]
            push!(results, """
            Email #$idx:
            Message ID: $(email.message_id)
            Thread ID: $(email.thread_id)
            Subject: $(email.subject)
            From: $(email.from)
            Date: $(email.date)
            
            $chunk
            """)
        end
        "Reranked email results for '$(tool.query)':\n\n$(join(results, "\n" * "-"^50 * "\n"))"
    end
EasyContext.tool_format(::Type{GmailSearchTool}) = :single_line

