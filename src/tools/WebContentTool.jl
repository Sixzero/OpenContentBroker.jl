using ToolCallFormat: @deftool

# Module-level adapter
const WEB_CONTENT_ADAPTER = DictCacheLayer(MarkdownifyAdapter())

@deftool "Extracts readable text content from a webpage" function read_url("URL of webpage to read" => url::String)
    content = OpenCacheLayer.get_content(WEB_CONTENT_ADAPTER, url)
    "Content from '$url':\n\n$(content.content)"
end

# Alias for backward compatibility
const WebContentTool = ReadUrlTool
