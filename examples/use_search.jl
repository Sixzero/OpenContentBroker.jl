using OpenContentBroker
using OpenContentBroker: LLMSearchEval
using OpenCacheLayer
using Dates

# Initialize adapters
tavily = TavilyAdapter(ENV["TAVILY_API_KEY"], 5)
jina = JinaAdapter(ENV["JINA_API_KEY"])
serp = SerpAdapter(ENV["SERP_API_KEY"])
# Initialize LLMSearchEval without API key as it uses aigenerate from OpenCacheLayer
llm_eval = LLMSearchEval()

# Wrap with cache
cached_tavily = DictCacheLayer(tavily)
cached_jina = DictCacheLayer(jina)
cached_serp = DictCacheLayer(serp)

function search_and_compare(query::String)
    println("\nSearching for: ", query)
    println("=" ^ 50)
    
    # Search with all engines
    tavily_results = get_content(cached_tavily, query)
    jina_results = get_content(cached_jina, query)
    serp_results = get_content(cached_serp, query)
    
    # Collect results for evaluation
    results_by_engine = Dict(
        "Tavily" => tavily_results,
        "Jina" => jina_results,
        "SERP" => serp_results
    )
    
    # Display results
    for (name, results) in results_by_engine
        println("\n$name Results:")
        println("-" ^ 30)
        for result in results
            println("Title: ", result.title)
            println("URL: ", result.url)
            println("Score: ", result.score)
            println("-" ^ 20)
        end
    end
    
    # Get evaluation
    println("\nLLM Evaluation:")
    println("=" ^ 50)
    evaluation = evaluate_search_results(llm_eval, query, results_by_engine)
    println(evaluation)
end

# Test the search
search_and_compare("Julia programming language features")
