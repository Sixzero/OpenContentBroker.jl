using HTTP
using JSON3
using Dates
using OpenCacheLayer

@kwdef struct LLMSearchEval
    model::String = "claude"
    temperature::Float64 = 0.1
    top_p::Float64 = 0.1
    readtimeout::Int = 120
end

function evaluate_search_results(adapter::LLMSearchEval, query::String, results_by_engine::Dict)
    prompt = """
    As a search quality evaluator, analyze these search results for the query: "$query"
    
    Here are the search results from different engines:
    
    $(join(["""
    === $(engine) Results ===
    $(join(["Title: $(r.title)\nURL: $(r.url)\nContent: $(r.content)" 
            for r in results], "\n\n"))
    """ for (engine, results) in results_by_engine], "\n\n"))
    
    Please evaluate the quality and relevance of each search engine's results.
    Rate them on a scale of 1-10 and explain your reasoning briefly.
    Focus on: relevance, diversity, information quality, and usefulness for the query.
    
    Format your response as:
    Engine: Score - Brief explanation
    
    Finally, rank the engines from best to worst for this specific query.
    """
    
    resp = aigenerate(prompt; 
        model=adapter.model,
        http_kwargs=(; readtimeout=adapter.readtimeout),
        api_kwargs=(; temperature=adapter.temperature, top_p=adapter.top_p)
    )
    return resp.content
end
