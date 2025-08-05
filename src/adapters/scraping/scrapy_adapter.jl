using HTTP
using JSON3
using OpenCacheLayer
using OpenCacheLayer: VALID, ASYNC
using Dates
using Scratch

@kwdef struct ScrapyAdapter <: AbstractUrl2LLMAdapter
    python_script_path::String = get_scrapy_script_path()
end

struct ScrapyContent <: AbstractWebContent
    url::String
    content::String
    metadata::Dict{Symbol,Any}
    timestamp::DateTime
end

function get_scrapy_script_path()
    scratch_dir = @get_scratch!("scrapy_scripts")
    script_path = joinpath(scratch_dir, "scrapy_markdown.py")
    
    if !isfile(script_path)
        create_scrapy_script(script_path)
    end
    
    return script_path
end

function create_scrapy_script(script_path::String)
    script_content = """
import scrapy
import sys
import json
from markdownify import markdownify as md

class QuickSpider(scrapy.Spider):
    name = 'quick'
    
    def __init__(self, url=None, *args, **kwargs):
        super(QuickSpider, self).__init__(*args, **kwargs)
        self.start_urls = [url] if url else []
    
    def parse(self, response):
        result = {
            'url': response.url,
            'content': md(response.text, heading_style="ATX"),
        }
        print(json.dumps(result, ensure_ascii=False))

if __name__ == '__main__':
    from scrapy.crawler import CrawlerProcess
    import logging
    
    # Suppress all scrapy logs
    logging.getLogger('scrapy').setLevel(logging.CRITICAL)
    logging.getLogger('twisted').setLevel(logging.CRITICAL)
    
    if len(sys.argv) < 2:
        print(json.dumps({'error': 'No URL provided'}))
        sys.exit(1)
    
    url = sys.argv[1]
    process = CrawlerProcess({
        'USER_AGENT': 'Mozilla/5.0 (compatible; ScrapyBot)',
        'LOG_LEVEL': 'CRITICAL',
        'LOG_ENABLED': False
    })
    
    process.crawl(QuickSpider, url=url)
    process.start()
"""
    
    write(script_path, script_content)
    
    # Install requirements
    run(`python3 -m pip install scrapy markdownify`)
end

function OpenCacheLayer.get_content(adapter::ScrapyAdapter, url::String)
    try
        # Run the script and capture both stdout and stderr
        result = read(`python3 $(adapter.python_script_path) $url`, String)
        
        # Find the JSON output - look for the first { and parse from there
        json_start = findfirst('{', result)
        if json_start === nothing
            @warn "No JSON output found from Scrapy for $url"
            return ScrapyContent(url, "No JSON output", Dict{Symbol,Any}(:error => "No JSON output"), now())
        end
        
        # Extract JSON from the first { to the end, then parse
        json_text = result[json_start:end]
        response = JSON3.read(json_text)
        
        if haskey(response, :error)
            @warn "Scrapy scraping failed for $url: $(response.error)"
            ScrapyContent(
                url,
                response.error,
                Dict{Symbol,Any}(:error => response.error),
                now()
            )
        else
            ScrapyContent(
                url,
                response.content,
                Dict{Symbol,Any}(),
                now()
            )
        end
    catch e
        @warn "Failed to execute Scrapy script for $url: $e"
        ScrapyContent(
            url,
            "Script execution failed: $e",
            Dict{Symbol,Any}(:error => "Script execution failed: $e"),
            now()
        )
    end
end

OpenCacheLayer.get_timestamp(content::ScrapyContent) = content.timestamp
OpenCacheLayer.get_adapter_hash(adapter::ScrapyAdapter) = "SCRAPY_" * string(hash(adapter.python_script_path))

function OpenCacheLayer.is_cache_valid(content::ScrapyContent, adapter::ScrapyAdapter)
    ASYNC # its free to request.
end