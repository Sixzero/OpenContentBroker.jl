using HTTP
using JSON3
using OpenCacheLayer
using OpenCacheLayer: VALID, ASYNC
using Dates
using Scratch

@kwdef struct CrawleeAdapter <: AbstractUrl2LLMAdapter
    node_script_path::String = get_crawlee_script_path()
    timeout::Int = 15
    max_concurrency::Int = 30
    use_readability::Bool = true
    remove_elements::Vector{String} = ["script", "style", "nav", "footer", ".ads", ".advertisement", ".cookie"]
end

struct CrawleeContent <: AbstractWebContent
    url::String
    content::String
    metadata::Dict{Symbol,Any}
    timestamp::DateTime
end

function get_crawlee_script_path()
    # Get or create a scratch directory for our Node.js scripts
    scratch_dir = @get_scratch!("crawlee_scripts")
    script_path = joinpath(scratch_dir, "crawl2md.mjs")
    @show script_path
    
    # Create the Node.js script if it doesn't exist
    if !isfile(script_path)
        create_crawlee_script(script_path)
    end
    
    return script_path
end

function create_crawlee_script(script_path::String)
    script_content = """
import { CheerioCrawler, PlaywrightCrawler } from 'crawlee';
import TurndownService from 'turndown';
import { gfm } from 'turndown-plugin-gfm';
import { Readability } from '@mozilla/readability';
import { JSDOM } from 'jsdom';
import { log } from 'crawlee';

// Suppress all logging by setting log level to OFF
log.setLevel('OFF');

// Parse command line arguments
const args = process.argv.slice(2);
const config = JSON.parse(args[0]);

const td = new TurndownService({ 
    headingStyle: 'atx', 
    codeBlockStyle: 'fenced' 
});
td.use(gfm);

// Remove unwanted elements
config.remove_elements.forEach(selector => {
    td.remove(selector);
});

async function scrapeUrl(url, useReadability = true, useDynamic = false) {
    let content = '';
    let metadata = {};
    
    try {
        if (useDynamic) {
            // Use Playwright for dynamic content
            const crawler = new PlaywrightCrawler({
                headless: true,
                maxConcurrency: config.max_concurrency,
                async requestHandler({ request, page }) {
                    await page.goto(request.url, { waitUntil: 'networkidle' });
                    const html = await page.content();
                    
                    if (useReadability) {
                        const dom = new JSDOM(html, { url: request.loadedUrl });
                        const reader = new Readability(dom.window.document);
                        const article = reader.parse();
                        
                        if (article) {
                            content = td.turndown(article.content);
                            metadata = {
                                title: article.title,
                                excerpt: article.excerpt,
                                byline: article.byline,
                                length: article.length
                            };
                        } else {
                            content = td.turndown(html);
                        }
                    } else {
                        content = td.turndown(html);
                    }
                }
            });
            
            await crawler.run([url]);
        } else {
            // Use Cheerio for static content
            const crawler = new CheerioCrawler({
                maxConcurrency: config.max_concurrency,
                async requestHandler({ request, \$ }) {
                    // Remove unwanted elements
                    config.remove_elements.forEach(selector => {
                        \$(selector).remove();
                    });
                    
                    const html = \$('main').html() || \$('article').html() || \$.html();
                    content = td.turndown(html);
                    
                    metadata = {
                        title: \$('title').text() || \$('h1').first().text(),
                        description: \$('meta[name="description"]').attr('content') || ''
                    };
                }
            });
            
            await crawler.run([url]);
        }
        
        // Only output JSON to stdout
        process.stdout.write(JSON.stringify({
            success: true,
            content: content,
            metadata: metadata
        }));
        
    } catch (error) {
        process.stdout.write(JSON.stringify({
            success: false,
            error: error.message,
            content: '',
            metadata: {}
        }));
    }
}

// Execute scraping
scrapeUrl(config.url, config.use_readability, config.use_dynamic);
"""
    
    write(script_path, script_content)
    
    # Also create package.json if it doesn't exist
    package_json_path = joinpath(dirname(script_path), "package.json")
    if !isfile(package_json_path)
        package_json = """
{
  "type": "module",
  "dependencies": {
    "crawlee": "^3.14.0",
    "turndown": "^7.2.0",
    "turndown-plugin-gfm": "^1.0.2",
    "@mozilla/readability": "^0.4.4",
    "jsdom": "^22.1.0",
    "playwright": "^1.40.0"
  }
}
"""
        write(package_json_path, package_json)
        
        # Install dependencies
        run(`npm install --prefix $(dirname(script_path))`)
    end
end

function OpenCacheLayer.get_content(adapter::CrawleeAdapter, url::String)
    config = Dict(
        "url" => url,
        "max_concurrency" => adapter.max_concurrency,
        "use_readability" => adapter.use_readability,
        "remove_elements" => adapter.remove_elements,
        "use_dynamic" => false  # Start with static, could be made configurable
    )
    
    try
        # Run the Node.js script
        @time result = read(`node $(adapter.node_script_path) $(JSON3.write(config))`, String)
        
        # Extract JSON by looking for {"success" pattern
        json_start = findfirst("{\"success\"", result)
        if json_start !== nothing
            json_part = result[json_start[1]:end]
            response = JSON3.read(json_part)
            
            if response.success
                CrawleeContent(
                    url,
                    response.content,
                    Dict{Symbol,Any}(response.metadata),
                    now()
                )
            else
                @warn "Crawlee scraping failed for $url: $(response.error)"
                CrawleeContent(
                    url,
                    "",
                    Dict{Symbol,Any}(:error => response.error),
                    now()
                )
            end
        else
            @warn "No JSON found in Crawlee output for $url"
            CrawleeContent(
                url,
                "",
                Dict{Symbol,Any}(:error => "No JSON output found"),
                now()
            )
        end
    catch e
        @warn "Failed to execute Crawlee script for $url: $e"
        CrawleeContent(
            url,
            "",
            Dict{Symbol,Any}(:error => "Script execution failed: $e"),
            now()
        )
    end
end

OpenCacheLayer.get_timestamp(content::CrawleeContent) = content.timestamp
OpenCacheLayer.get_adapter_hash(adapter::CrawleeAdapter) = "CRAWLEE_" * string(hash(adapter.node_script_path))

# Cache validity - similar to Firecrawl
function OpenCacheLayer.is_cache_valid(content::CrawleeContent, adapter::CrawleeAdapter)
    ASYNC # its free to request.
end