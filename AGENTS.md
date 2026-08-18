# Agent notes

## LLM hívások: mindig cliproxy-n át (ingyen van)

Standalone script/teszt futtatás előtt:

```julia
using OpenRouterCLIProxyAPI
setup_cli_proxy!(mutate=true)
```

Ez az anthropic/openai/xai providereket a helyi cliproxyapi-ra (localhost:8317, OAuth) irányítja — direkt API-hívás helyett, ami pénzbe kerül. `mutate=true` nélkül a `anthropic:...` modellek direktben az api.anthropic.com-ra mennek az API-kulccsal.
