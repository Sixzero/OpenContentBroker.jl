#!/usr/bin/env python3
from markdownify import markdownify as md

def test_markdown_splitting():
    """Test how markdownify handles paragraph splitting"""
    
    test_html = '''<table border="0" class="comment-tree"><tbody><tr class="athing comtr" id="44804397"><td><table border="0"><tbody><tr><td class="ind" indent="0"><img src="s.gif" height="1" width="0"></td><td valign="top" class="votelinks"><center><a id="up_44804397" href="vote?id=44804397&amp;how=up&amp;goto=item%3Fid%3D44800746"><div class="votearrow" title="upvote"></div></a></center></td><td class="default"><div style="margin-top:2px; margin-bottom:-10px;"><span class="comhead"><a href="user?id=cco" class="hnuser">cco</a> <span class="age" title="2025-08-05T21:13:25 1754428405"><a href="item?id=44804397">10 hours ago</a></span> <span id="unv_44804397"></span><span class="navs"> | <a href="#44801714" class="clicky" aria-hidden="true">next</a> <a class="togg clicky" id="44804397" n="135" href="javascript:void(0)">[–]</a><span class="onstory"></span></span></span></div><br>
<div class="comment"><div class="commtext c00">The lede is being missed imo.<p>gpt-oss:20b is a top ten model (on MMLU (right behind Gemini-2.5-Pro) and I just ran it locally on my Macbook Air M3 from last year.</p><p>I've been experimenting with a lot of local models, both on my laptop and on my phone (Pixel 9 Pro), and I figured we'd be here in a year or two.</p><p>But no, we're here today. A basically frontier model, running for the cost of electricity (free with a rounding error) on my laptop. No $200/month subscription, no lakes being drained, etc.</p><p>I'm blown away.</p></div><div class="reply"><p><font size="1"><u><a href="reply?id=44804397&amp;goto=item%3Fid%3D44800746%2344804397" rel="nofollow">reply</a></u></font></p></div></div></td></tr></tbody></table></td></tr><tr class="athing comtr" id="44802125"><td><table border="0"><tbody><tr><td class="ind" indent="0"><img src="s.gif" height="1" width="0"></td><td valign="top" class="votelinks"><center><a id="up_44802125" href="vote?id=44802125&amp;how=up&amp;goto=item%3Fid%3D44800746"><div class="votearrow" title="upvote"></div></a></center></td><td class="default"><div style="margin-top:2px; margin-bottom:-10px;"><span class="comhead"><a href="user?id=ahmetcadirci25" class="hnuser">ahmetcadirci25</a> <span class="age" title="2025-08-05T18:25:07 1754418307"><a href="item?id=44802125">13 hours ago</a></span> <span id="unv_44802125"></span><span class="navs"> | <a href="#44800968" class="clicky" aria-hidden="true">prev</a> <a class="togg clicky" id="44802125" n="1" href="javascript:void(0)">[–]</a><span class="onstory"></span></span></span></div><br>
<div class="comment"><div class="commtext cBE">I started downloading, I'm eager to test it. I will share my personal experiences. <a href="https://ahmetcadirci.com/2025/gpt-oss/" rel="nofollow">https://ahmetcadirci.com/2025/gpt-oss/</a></div><div class="reply"><p><font size="1"><u><a href="reply?id=44802125&amp;goto=item%3Fid%3D44800746%2344802125" rel="nofollow">reply</a></u></font></p></div></div></td></tr></tbody></table></td></tr></tbody></table>'''
    
    
    # Test with different markdownify settings
    configs = [
        {"heading_style": "ATX"},
        {"heading_style": "ATX", "strip": ["table", "tbody", "tr", "td", "th", "thead"]},
    ]
    
    for i, config in enumerate(configs, 1):
        print(f"Config {i}: {config}")
        markdown_result = md(test_html, **config)
        print("\nFormatted output:")
        print(markdown_result)
        print("\n" + "-"*30 + "\n")

if __name__ == "__main__":
    test_markdown_splitting()