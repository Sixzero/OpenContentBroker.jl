using ToolCallFormat: @deftool

# Lazy-initialized adapter (avoid BaseDirs call during precompilation)
const _WEB_CONTENT_ADAPTER = Ref{Union{DictCacheLayer{MarkdownifyAdapter},Nothing}}(nothing)
function get_web_content_adapter()
    _WEB_CONTENT_ADAPTER[] === nothing && (_WEB_CONTENT_ADAPTER[] = DictCacheLayer(MarkdownifyAdapter()))
    _WEB_CONTENT_ADAPTER[]
end

@deftool "Extracts readable text content from a webpage" function web_content("URL of webpage to read" => url::String)
    content = OpenCacheLayer.get_content(get_web_content_adapter(), url)
    "Content from '$url':\n\n$(content.content)"
end

# Alias for backward compatibility (web_content → WebContentTool via CamelCase)
const ReadUrlTool = WebContentTool
