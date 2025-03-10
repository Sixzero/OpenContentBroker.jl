using HTTP
using URIs
using OpenCacheLayer
using PromptingTools

# Abstract strategy for relevance checking
abstract type RelevanceStrategy end

# Simple keyword-based relevance checker
struct KeywordRelevanceStrategy <: RelevanceStrategy
    threshold::Float64
end

KeywordRelevanceStrategy() = KeywordRelevanceStrategy(0.1)

# AI-based relevance checker using PromptingTools
struct AIRelevanceStrategy <: RelevanceStrategy
    model::String
    threshold::Float64
end

AIRelevanceStrategy(; model="dscode", threshold=0.6) = AIRelevanceStrategy(model, threshold)

struct WebScrapedContent <: AbstractWebContent
    url::String
    content::String
    summary::String
    topic::String
    related_urls::Dict{String,String}
    timestamp::DateTime
end

struct WebScraperAdapter <: StatusBasedAdapter
    web_adapter::AbstractUrl2LLMAdapter
    max_depth::Int
    max_urls::Int
    relevance_strategy::RelevanceStrategy
    topic::String
end

# Enhanced constructor
function WebScraperAdapter(; 
    headers=Dict{String,String}(), 
    cache_policy=RESPECT,
    max_depth=3,
    max_urls=10,
    relevance_strategy=AIRelevanceStrategy(),
    topic="")
    WebScraperAdapter(
        RawWebAdapter(headers, cache_policy), 
        max_depth, 
        max_urls, 
        relevance_strategy,
        topic
    )
end

# Implement relevance checking for keyword strategy
function check_relevance(strategy::KeywordRelevanceStrategy, content::String, main_content::String, topic::String)
    main_words = Set(lowercase.(split(main_content)))
    content_words = Set(lowercase.(split(content)))
    overlap = length(intersect(main_words, content_words)) / length(main_words)
    overlap > strategy.threshold
end

# Implement relevance checking for AI strategy
function check_relevance(strategy::AIRelevanceStrategy, content::String, main_content::String, topic::String)
    @show length(content)
    # Split content into larger chunks (40k chars)
    chunks = recursive_splitter(content, ["\n\n", "\n"]; max_length=40000)
    
    # Prepare XML formatted content
    xml_docs = String[]
    for (idx, chunk) in enumerate(chunks)
        xml_doc = """
        <doc idx="$idx" url="$(topic):$(idx*40000-39999)-$(idx*40000)">
        $(chunk)
        </doc>
        """
        push!(xml_docs, xml_doc)
    end
    
    # Process chunks in batches of ~50k total chars
    scores = Dict{Int,Float64}()
    current_batch = String[]
    current_length = 0
    
    for doc in xml_docs
        if current_length + length(doc) > 50000 && !isempty(current_batch)
            # Process current batch
            batch_scores = process_batch(strategy, join(current_batch, "\n"), topic)
            merge!(scores, batch_scores)
            current_batch = String[]
            current_length = 0
        end
        push!(current_batch, doc)
        current_length += length(doc)
    end
    
    # Process remaining batch
    if !isempty(current_batch)
        batch_scores = process_batch(strategy, join(current_batch, "\n"), topic)
        merge!(scores, batch_scores)
    end
    
    # Return false if no valid scores
    isempty(scores) && return false
    
    # Use mean score to determine relevance
    mean(values(scores)) > strategy.threshold
end

function process_batch(strategy::AIRelevanceStrategy, content::String, topic::String)
    prompt = """
    Context: Analyzing web content for topic relevance.
    Main topic: $topic
    
    Task: Analyze the relevance of each document to the main topic.
    Return a JSON dictionary mapping document indices to relevance scores (0 to 1).
    Format: {"1": 0.8, "2": 0.4, ...}
    
    Documents to analyze:
    $content
    """
    
    response = aigenerate(prompt; model=strategy.model)
    
    try
        # Parse JSON response to get scores dictionary
        scores_str = match(r"\{[^}]+\}", response.content).match
        scores_dict = JSON.parse(scores_str)
        # Convert string keys to Int keys
        return Dict(parse(Int, k) => Float64(v) for (k,v) in scores_dict)
    catch e
        @warn "Failed to parse AI response for batch: $e"
        return Dict{Int,Float64}()
    end
end

# Extract URLs from HTML content
function extract_urls(content::String, base_url::String)
    urls = String[]
    for m in eachmatch(r"href=['\"]([^'\"]+)['\"]", content)
        url = m.captures[1]
        try
            full_url = URIs.absurl(url, base_url)
            URIs.scheme(full_url) in ("http", "https") && push!(urls, string(full_url))
        catch
            continue
        end
    end
    unique(urls)
end

# Recursive content fetching with depth tracking
function fetch_related_content(adapter::WebScraperAdapter, url::String, main_content::String, 
                             visited::Set{String}=Set{String}(); current_depth::Int=1)
    current_depth > adapter.max_depth && return Dict{String,String}()
    url in visited && return Dict{String,String}()
    
    push!(visited, url)
    @info "Scraping $url (depth: $current_depth)"
    
    try
        content = get_content(adapter.web_adapter, url)
        if !check_relevance(adapter.relevance_strategy, content.content, main_content, adapter.topic)
            return Dict{String,String}()
        end
        
        results = Dict(url => content.content)
        
        if current_depth < adapter.max_depth
            urls = extract_urls(content.content, url)
            for next_url in urls[1:min(length(urls), adapter.max_urls)]
                merge!(results, 
                    fetch_related_content(adapter, next_url, main_content, visited; 
                                       current_depth=current_depth + 1))
                
                length(results) >= adapter.max_urls && break
            end
        end
        
        return results
    catch e
        @warn "Failed to fetch $url: $e"
        return Dict{String,String}()
    end
end

function OpenCacheLayer.get_content(adapter::WebScraperAdapter, url::String)
    @info "Starting scrape of main URL: $url"
    
    # Get main content
    main_content = get_content(adapter.web_adapter, url)
    
    # Recursively fetch related content
    related_contents = fetch_related_content(adapter, url, main_content.content)
    
    # Create simple summary
    summary = first(main_content.content, 500) * "..."
    
    WebScrapedContent(
        url,
        main_content.content,
        summary,
        adapter.topic,
        related_contents,
        now()
    )
end

# Interface methods
OpenCacheLayer.get_timestamp(content::WebScrapedContent) = content.timestamp
OpenCacheLayer.is_cache_valid(content::WebScrapedContent, adapter::WebScraperAdapter) = 
    is_cache_valid(WebContent("", "", UInt8[], nothing, nothing, nothing, content.timestamp), 
                  adapter.web_adapter)
OpenCacheLayer.get_adapter_hash(adapter::WebScraperAdapter) = 
    "WEBSCRAPER_" * get_adapter_hash(adapter.web_adapter)
