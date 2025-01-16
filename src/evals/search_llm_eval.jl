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
    
    Evaluate each search engine's results on these metrics (score 1-10):
    1. Relevance: How well do results match the query intent?
    2. Information Quality: Accuracy, authority, and reliability of sources
    3. Result Diversity: Variety of perspectives and source types, whether something mentioned that is important but others missed out on it
    4. Query-specific Usefulness: Practical value for this specific query
    
    Format your response with scores and brief explanations:
    {
        "Engine1": {
            "relevance": score,
            "quality": score,
            "diversity": score,
            "usefulness": score,
            "overall": average_score
        },
        ...
    }
    
    Then provide a brief explanation of your ranking.
    """
    
    resp = aigenerate(prompt; 
        model=adapter.model,
        http_kwargs=(; readtimeout=adapter.readtimeout),
        api_kwargs=(; temperature=adapter.temperature, top_p=adapter.top_p)
    )

    return resp.content
end
