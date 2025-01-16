# OpenContentBroker [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://sixzero.github.io/OpenContentBroker.jl/stable/) [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://sixzero.github.io/OpenContentBroker.jl/dev/) [![Build Status](https://github.com/sixzero/OpenContentBroker.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/sixzero/OpenContentBroker.jl/actions/workflows/CI.yml?query=branch%3Amaster) [![Coverage](https://codecov.io/gh/sixzero/OpenContentBroker.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/sixzero/OpenContentBroker.jl) [![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

## Search Capabilities

The package provides a unified interface to multiple search engines with quality evaluation:

### Available Search Engines
- Tavily Search
- SERP API (Google, Bing, Yandex, Baidu, Yahoo)
- DuckDuckGo
- Google Custom Search
- Jina AI Search

### Search Quality Evaluation
Includes LLM-based search quality evaluation tools:
```julia
# Initialize different search engines
engines = Dict(
    "Tavily" => DictCacheLayer(TavilyAdapter()),
    "SERP_Bing" => DictCacheLayer(SerpAdapter(engine="bing")),
    "DDG" => DictCacheLayer(DDGAdapter())
)

# Evaluate and compare search results
plot_search_engine_scores()  # Generates comparison plot
```

The evaluation compares search engines based on:
- Relevance
- Information quality
- Result diversity
- Query-specific usefulness

Results are plotted with error bars showing consistency across multiple queries.
