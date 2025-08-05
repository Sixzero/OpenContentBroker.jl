#!/usr/bin/env python3
import time
import requests
from markdownify import markdownify as md

def time_markdownify_scraping(url):
    """Time how long it takes to scrape and convert to markdown"""
    start_time = time.time()
    
    # Fetch the webpage
    response = requests.get(url, headers={
        'User-Agent': 'Mozilla/5.0 (compatible; MarkdownifyBot)'
    })
    response.raise_for_status()
    
    # Convert to markdown
    markdown_content = md(response.text, heading_style="ATX")
    
    end_time = time.time()
    duration = end_time - start_time
    
    return {
        'url': url,
        'duration': duration,
        'content_length': len(markdown_content),
        'html_length': len(response.text),
        'markdown_content': markdown_content
    }

def main():
    urls = [
        "https://quotes.toscrape.com/tag/miracles/page/1/",
        "https://apify.com/store",
        "https://python.langchain.com/docs/integrations/document_transformers/markdownify/",
    ]
    
    print("🕐 Markdownify Timing Test")
    print("=" * 40)
    
    for url in urls:
        print(f"\nTesting: {url}")
        try:
            result = time_markdownify_scraping(url)
            print(f"⏱️  Duration: {result['duration']:.3f}s")
            print(f"📄 HTML length: {result['html_length']:,} chars")
            print(f"📝 Markdown length: {result['content_length']:,} chars")
            print(f"📊 Compression ratio: {result['content_length']/result['html_length']:.2%}")
            
            # Show first 200 chars of markdown
            preview = result['markdown_content'][:200].replace('\n', '\\n')
            print(f"🔍 Preview: {preview}...")
            
        except Exception as e:
            print(f"❌ Error: {e}")

if __name__ == "__main__":
    main()