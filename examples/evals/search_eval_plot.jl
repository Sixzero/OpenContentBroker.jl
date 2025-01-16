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
    
    start_idx == 0 && return Dict{String,Float64}()
    
    # Extract the JSON part
    cleaned = strip(text[start_idx:end_idx])
    
    try
        result = Dict{String,Float64}()
        for (k,v) in JSON3.read(cleaned)
            # Convert Symbol key to String
            key = String(k)
            # Handle both numeric and string values
            score = v isa Number ? Float64(v) : parse(Float64, string(v))
            result[key] = score
        end
        return result
    catch e
        println("\nFailed to parse LLM response:")
        println("Text:\n", text)
        println("\nCleaned:\n", cleaned)
        println("\nException:\n", sprint(showerror, e, catch_backtrace()), "\n")
        return Dict{String,Float64}()
    end
end

function extract_scores_from_llm(eval_text, engine_names)
    prompt = """
    Extract search engine scores from this evaluation text and return them in JSON format. 
    Each engine should be a key with its numerical score (1-10) as value.
    Only use these exact engine names as keys: $(join(engine_names, ", ")).
    
    # Evaluation text:
    $eval_text

    # Return format example:
    {
        $(join(["\"$name\": 7.5" for name in engine_names], ",\n    "))
    }
    """
    
    content = aigenerate(prompt; model="gem20f", api_kwargs=(; temperature=0.1)).content
    scores = parse_llm_scores(content)
    
    # Validate all engines are present
    missing_engines = setdiff(engine_names, keys(scores))
    if !isempty(missing_engines)
        println("\nMissing scores for engines:\n", join(missing_engines, ", "), "\n")
        # Set default score for missing engines
        for engine in missing_engines
            scores[engine] = 5.0  # neutral score as fallback
        end
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
    # Convert engines dict to vector of pairs for asyncmap
    engine_pairs = collect(pairs(engines))
    
    # Get search results asynchronously
    results = Dict{String,Vector{Any}}()
    asyncmap(engine_pairs) do (name, engine)
        results[name] = get_content(engine, query)
    end
    
    evaluation = evaluate_search_results(llm_eval, query, results)
    res = extract_scores_from_llm(evaluation, keys(engines))
    res
end

function aggregate_scores(scores_collection)
    all_scores = Dict{String,Vector{Float64}}()
    for scores in scores_collection
        for (engine, score) in scores
            push!(get!(all_scores, engine, Float64[]), score)
        end
    end
    all_scores
end

function create_plot(avg_scores, std_scores)
    # Sort by mean scores in descending order
    sorted_pairs = sort(collect(pairs(avg_scores)), by=last, rev=true)
    names = first.(sorted_pairs)
    means = last.(sorted_pairs)
    stds = [std_scores[n] for n in names]

    bar(names, means,
        title="Search Engine Performance Comparison",
        xlabel="Search Engine",
        ylabel="Average Score (1-10)",
        legend=false,
        rotation=45,
        color=:lightblue,
        yerror=stds,
        size=(800, 600))
end

function plot_search_engine_scores(queries=String[]; 
    save_path="search_engine_scores.png", 
    llm_eval=LLMSearchEval())
    
    queries = isempty(queries) ? DEFAULT_QUERIES : queries
    engines = init_engines()
    
    # Collect and evaluate all queries asynchronously
    scores_collection = asyncmap(query -> evaluate_query(engines, query, llm_eval), queries)

    
    # Aggregate scores
    all_scores = aggregate_scores(scores_collection)
    
    # Calculate statistics
    avg_scores = Dict(engine => mean(scores) for (engine, scores) in all_scores)
    std_scores = Dict(engine => std(scores) for (engine, scores) in all_scores)

    # Create and save plot
    p = create_plot(avg_scores, std_scores)
    savefig(p, save_path)
    
    return p, avg_scores, std_scores
end

# Example usage:
res = plot_search_engine_scores()