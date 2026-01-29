# Module-level adapter
const WEB_CONTENT_ADAPTER = DictCacheLayer(MarkdownifyAdapter())

"Extracts readable text content from a webpage"
@deftool WebContentTool read_url(url::String) = begin
    content = OpenCacheLayer.get_content(WEB_CONTENT_ADAPTER, url)
    tool.result = "Content from '$url':\n\n$(content.content)"
end
