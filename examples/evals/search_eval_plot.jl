using Plots
using PromptingTools
using Statistics
using OpenCacheLayer
using JSON3
using OpenContentBroker
using OpenContentBroker: LLMSearchEval, evaluate_search_results
using Base.Iterators: product

function parse_llm_scores(text)
    # Extract JSON block between first { or [ and last } or ]
    start_idx = something(findfirst(c -> c in "{[", text), 0)
    end_idx = something(findlast(c -> c in "}]", text), 0)
    
    start_idx == 0 && return Dict{String,Dict{String,Float64}}()
    
    # Extract the JSON part
    cleaned = strip(text[start_idx:end_idx])
    
    try
        result = Dict{String,Dict{String,Float64}}()
        parsed = JSON3.read(cleaned)
        for (engine, scores) in parsed
            # Convert all scores to Float64
            result[String(engine)] = Dict{String,Float64}(
                String(k) => Float64(v) for (k,v) in scores
            )
        end
        return result
    catch e
        println("\nFailed to parse LLM response:")
        println("Text:\n", text)
        println("\nCleaned:\n", cleaned)
        println("\nException:\n", sprint(showerror, e, catch_backtrace()), "\n")
        return Dict{String,Dict{String,Float64}}()
    end
end

function extract_scores_from_llm(eval_text, engine_names)
    prompt = """
    Extract search engine scores from this evaluation text and return them in JSON format. 
    Each engine should be a key with its numerical score (1-10) as value.  The scores should be a dictionary with keys: relevance, quality, diversity, freshness, overall.
    Only use these exact engine names as keys: $(join(engine_names, ", ")).
    
    # Evaluation text:
    $eval_text

    # Return format example:
    {
        $(join(["\"$name\": {\"relevance\": 7.5, \"quality\": 8.0, \"diversity\": 6.5, \"freshness\": 7.0, \"overall\": 7.2}" for name in engine_names], ",\n    "))
    }
    """
    
    content = aigenerate(prompt; model="gem20f", api_kwargs=(; temperature=0.1)).content
    scores = parse_llm_scores(content)
    
    # Validate all engines are present
    missing_engines = setdiff(engine_names, keys(scores))
    if !isempty(missing_engines)
        error("Failed to get scores for engines: $(join(missing_engines, ", "))")
    end
    scores
end

const DEFAULT_QUERIES = [
    "Julia programming language features",
    "jld2 julia exclude field serialization",
    "documentation of serp api",
    "documentation of tavily",
    "documentation of google search api rest",
    "documentation of duckduckgo search api rest",
]

function init_engines()
    Dict(
        "Tavily" => DictCacheLayer(TavilyAdapter()),
        # "SERP_Google" => DictCacheLayer(SerpAdapter(engine="google")),
        "SERP_Bing" => DictCacheLayer(SerpAdapter(engine="bing")),
        "SERP_Yandex" => DictCacheLayer(SerpAdapter(engine="yandex")),
        "SERP_Baidu" => DictCacheLayer(SerpAdapter(engine="baidu")),
        "SERP_Yahoo" => DictCacheLayer(SerpAdapter(engine="yahoo")),
        "DDG" => DictCacheLayer(DDGAdapter()),
        "Google" => DictCacheLayer(GoogleAdapter())
    )
end

get_search_results(engine_name, engine, query) = Dict(engine_name => get_content(engine, query))

function evaluate_query(engines, query, llm_eval)
    @show query
    # Convert engines dict to vector of pairs for asyncmap
    engine_pairs = collect(pairs(engines))
    
    # Get search results asynchronously
    results = Dict{String,Vector{Any}}()
    
    try
        asyncmap(engine_pairs) do (name, engine)
            results[name] = get_content(engine, query)
        end
        
        evaluation = evaluate_search_results(llm_eval, query, results)
        extract_scores_from_llm(evaluation, keys(engines))
    catch e
        @error "Failed to evaluate query" query exception=e
        rethrow()
    end
end

function aggregate_scores(scores_collection)
    all_scores = Dict{String,Dict{String,Vector{Float64}}}()
    metrics = ["relevance", "quality", "diversity", "freshness", "overall"]
    
    for scores in scores_collection
        for (engine, engine_scores) in scores
            if !haskey(all_scores, engine)
                all_scores[engine] = Dict(metric => Float64[] for metric in metrics)
            end
            for metric in metrics
                push!(all_scores[engine][metric], engine_scores[metric])
            end
        end
    end
    all_scores
end

function create_plot(avg_scores, std_scores)
    # Sort engines by overall score
    sorted_pairs = sort(collect(pairs(avg_scores)), by=p->p[2]["overall"], rev=true)
    engines = first.(sorted_pairs)
    metrics = ["relevance", "quality", "diversity", "freshness"]
    
    # Create 4 subplots
    plots = []
    for metric in metrics
        scores = [avg_scores[engine][metric] for engine in engines]
        errors = [std_scores[engine][metric] for engine in engines]
        
        p = bar(engines, scores,
            title=titlecase(metric),
            xlabel="",
            ylabel="Score (1-10)",
            legend=false,
            yerror=errors,
            rotation=45,
            color=:lightblue,
            bar_width=0.6,
            lw=0)
            
        push!(plots, p)
    end
    
    # Combine plots into a 2x2 layout
    plot(plots..., 
        layout=(2,2), 
        size=(1200, 800),
        margin=5Plots.mm)
end

function plot_search_engine_scores(queries=String[]; 
    save_path="search_engine_scores.png", 
    llm_eval=LLMSearchEval())
    
    queries = isempty(queries) ? DEFAULT_QUERIES : queries
    engines = init_engines()
    
    # Collect and evaluate all queries asynchronously
    scores_collection = map(query -> evaluate_query(engines, query, llm_eval), queries)

    
    # Aggregate scores
    all_scores = aggregate_scores(scores_collection)
    
    # Calculate statistics
    avg_scores = Dict(engine => Dict(metric => mean(scores) for (metric, scores) in engine_scores) for (engine, engine_scores) in all_scores)
    std_scores = Dict(engine => Dict(metric => std(scores) for (metric, scores) in engine_scores) for (engine, engine_scores) in all_scores)

    # Create and save plot
    p = create_plot(avg_scores, std_scores)
    savefig(p, save_path)
    
    return p, avg_scores, std_scores
end

# Example usage:
res = plot_search_engine_scores()