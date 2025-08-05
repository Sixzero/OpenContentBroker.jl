#!/usr/bin/env python3
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
        # Convert HTML to markdown
        content = md(response.text, heading_style="ATX")
        
        result = {
            'url': response.url,
            'title': response.css('title::text').get() or '',
            'content': content,
            'links': response.css('a::attr(href)').getall()
        }
        
        print(json.dumps(result, indent=2, ensure_ascii=False))

if __name__ == '__main__':
    from scrapy.crawler import CrawlerProcess
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python scrapy_markdown.py <URL>")
        sys.exit(1)
    
    url = sys.argv[1]
    process = CrawlerProcess({
        'USER_AGENT': 'Mozilla/5.0 (compatible; ScrapyBot)',
        'LOG_LEVEL': 'ERROR'
    })
    
    process.crawl(QuickSpider, url=url)
    process.start()