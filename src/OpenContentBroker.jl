module OpenContentBroker

using Dates
using Base64
using HTTP
using JSON3
using LLMRateLimiters: TokenEstimationMethod, airatelimited, RateLimiterRPM, RateLimiterTPM, CharCountDivTwo, estimate_tokens
using OpenCacheLayer
using OpenCacheLayer: AbstractCacheLayer
using EasyContext: AbstractRAGPipeline, AbstractTool, search
using EasyContext: create_voyage_embedder, TwoLayerRAG, ReduceGPTReranker, TopK, BM25Embedder, execute
using ToolCallFormat: @deftool, CodeBlock

using RAGTools
const RAG = RAGTools

include("token_storage.jl")
include("oauth2.jl")

include("chunks/HtmlChunker.jl")

abstract type AbstractUrl2LLMAdapter <: StatusBasedAdapter end

include("adapters/search_base.jl")
include("adapters/tavily_search.jl")
include("adapters/jina_search.jl")
include("adapters/ddg_search.jl")
include("adapters/serp_search.jl")
include("adapters/google_search.jl")
include("adapters/google_rag.jl")


include("adapters/gmail.jl")
include("adapters/gmail_sender.jl")
include("adapters/web.jl")
include("adapters/scraping/web_scraper.jl")
include("adapters/scraping/firecrawl_scraper.jl")
include("adapters/scraping/crawlee_adapter.jl")
include("adapters/scraping/scrapy_adapter.jl")
include("adapters/scraping/markdownify_adapter.jl")
include("evals/search_llm_eval.jl")

include("tools/GitingestTool.jl")
include("tools/SearchGitingestTool.jl")
include("tools/GmailSearchTool.jl")
include("tools/GmailSenderTool.jl")
include("tools/GoogleSearchTool.jl")
include("tools/GoogleRAGTool.jl")
include("tools/GoogleRAGToolGenerator.jl")
include("tools/WebscrapeSearchTool.jl")
include("tools/WebContentTool.jl")

include("adapters/imap_adapter.jl")

export get_content

# Export core types
export OAuth2Config, OAuth2Token, TokenStorage, FileStorage

# Export adapters
export GmailAdapter, GmailMessage
export GmailSenderAdapter, GmailSenderTool
export RawWebAdapter
export WebScraperAdapter
export TavilyAdapter, JinaAdapter, DDGAdapter, SerpAdapter, SearchResult, GoogleAdapter
export FirecrawlAdapter, CrawleeAdapter, ScrapyAdapter, MarkdownifyAdapter
export AIRelevanceStrategy
export GoogleSearchTool
export GoogleRAGTool, GoogleRAGToolGenerator, GoogleRAGToolWithAdapter
export GitingestTool, SearchGitingestTool
export WebContentTool
export GmailSearchTool, GmailSenderTool
export IMAPAdapter, IMAPMessage
export GoogleRAGAdapter, GoogleRAGResult
end
