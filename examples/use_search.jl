using OpenContentBroker
using OpenContentBroker: LLMSearchEval, evaluate_search_results
using OpenCacheLayer
using Dates

# Initialize adapters
tavily = TavilyAdapter()
jina = JinaAdapter()
serp_google = SerpAdapter(engine="google")
serp_bing = SerpAdapter(engine="bing")
serp_yandex = SerpAdapter(engine="yandex")
ddg = DDGAdapter()
google = GoogleAdapter()

# Wrap with cache
cached_tavily = DictCacheLayer(tavily)
cached_jina = DictCacheLayer(jina)
cached_serp_google = DictCacheLayer(serp_google)
cached_serp_bing = DictCacheLayer(serp_bing)
cached_serp_yandex = DictCacheLayer(serp_yandex)
cached_ddg = DictCacheLayer(ddg)
cached_google = DictCacheLayer(google)  # Add Google cache

# Initialize LLMSearchEval without API key as it uses aigenerate from OpenCacheLayer
llm_eval = LLMSearchEval()

function search_and_compare(query::String)
    println("\nSearching for: ", query)
    println("=" ^ 50)
    
    # Search with all engines
    @time tavily_results = get_content(cached_tavily, query)
    @time serp_google_results = get_content(cached_serp_google, query)
    @time serp_bing_results = get_content(cached_serp_bing, query)
    @time serp_yandex_results = get_content(cached_serp_yandex, query)
    @time ddg_results = get_content(cached_ddg, query)
    @time google_results = get_content(cached_google, query)
    
    # Collect results for evaluation
    results_by_engine = Dict(
        "Tavily" => tavily_results,
        "SERP_Google" => serp_google_results,
        "SERP_Bing" => serp_bing_results,
        "SERP_Yandex" => serp_yandex_results,
        "DDG" => ddg_results,
        "Google" => google_results
    )
    
    # Display results
    for (name, results) in results_by_engine
        println("\n$name Results:")
        println("-" ^ 30)
        for result in results
            println("Title: ", result.title)
            println("URL: ", result.url)
            # println("Score: ", result.score)
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
search_and_compare("jld2 julia exclude field serialization")
search_and_compare("documentation of serp api")
search_and_compare("documentation of jina search")
search_and_compare("documentation of tavily")
search_and_compare("documentation of google search api rest")
search_and_compare("documentation of duckduckgo search api rest")