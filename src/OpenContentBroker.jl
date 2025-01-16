module OpenContentBroker

using Dates
using Base64
using HTTP
using JSON3
using OpenCacheLayer

include("token_storage.jl")
include("oauth2.jl")

include("adapters/search_base.jl")
include("adapters/tavily_search.jl")
include("adapters/jina_search.jl")
include("adapters/ddg_search.jl")
include("adapters/serp_search.jl")
include("adapters/google_search.jl")

include("adapters/gmail.jl")
include("adapters/web.jl")
include("adapters/web_scraper.jl")
include("evals/search_llm_eval.jl")

# Export core types
export OAuth2Config, OAuth2Token, TokenStorage, FileStorage

# Export adapters
export GmailAdapter, GmailMessage
export WebAdapter
export WebScraperAdapter
export TavilyAdapter, JinaAdapter, DDGAdapter, SerpAdapter, SearchResult, GoogleAdapter
export AIRelevanceStrategy

end
