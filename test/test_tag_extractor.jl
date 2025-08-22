using Test
using EasyContext
using UUIDs
using EasyContext: ToolTagExtractor, ToolTag, extract_tool_calls, serialize
using EasyContext: SHELL_BLOCK_TAG, AbstractTool, instantiate
using OpenContentBroker: GoogleSearchTool, WebContentTool, GmailSenderTool, SearchGitingestTool

@testset failfast=true "ToolTagExtractor Tests 3rd party tools" begin
    @testset "Tool tags extraction test" begin
        parser = ToolTagExtractor([GoogleSearchTool, WebContentTool, GmailSenderTool, SearchGitingestTool])
        content = """
        Let's search and extract content:

        GOOGLE_SEARCH python cli tutorial $STOP_SEQUENCE
        
        READ_URL https://example.com/doc $STOP_SEQUENCE

        GMAIL_SEND
        ```
        To: test@example.com
        Subject: Test Subject
        Reply-To: reply@example.com

        Test email body content
        Multiple lines supported
        ```

        SEARCH_GITINGEST "pulling downloading files from github"
        ```urls
        https://github.com/cyclotruc/gitingest
        ```
        """

        extract_tool_calls(content, parser; kwargs=Dict("root_path" => "/test/root"), is_flush=true)
        
        @test length(parser.tool_tags) == 4
        
        google_tag = parser.tool_tags[1]
        @test google_tag.name == "GOOGLE_SEARCH"
        @test google_tag.args == "python cli tutorial"
        @test isempty(google_tag.content)

        web_tag = parser.tool_tags[2]
        @test web_tag.name == "READ_URL" 
        @test web_tag.args == "https://example.com/doc"
        @test isempty(web_tag.content)

        gmail_tag = parser.tool_tags[3]
        @test gmail_tag.name == "GMAIL_SEND"
        @test isempty(gmail_tag.args)
        @test contains(gmail_tag.content, "To: test@example.com")
        @test contains(gmail_tag.content, "Subject: Test Subject")
        @test contains(gmail_tag.content, "Test email body content")

        git_tag = parser.tool_tags[4]
        @test git_tag.name == "SEARCH_GITINGEST"
        @test git_tag.args == "pulling downloading files from github"
        @test strip(git_tag.content) == "```urls\nhttps://github.com/cyclotruc/gitingest\n```"
    end
    
    @testset "SearchGitingestTool URL parsing" begin
        # Test with code block format
        tag_with_codeblock = ToolTag(
            name="SEARCH_GITINGEST",
            args="test query",
            content="```urls\nhttps://github.com/user1/repo1\nhttps://github.com/user2/repo2\n```"
        )
        tool = SearchGitingestTool(tag_with_codeblock)
        @test length(tool.urls) == 2
        @test tool.urls[1] == "https://github.com/user1/repo1"
        @test tool.urls[2] == "https://github.com/user2/repo2"
        
        # Test with plain text format (no code block)
        tag_without_codeblock = ToolTag(
            name="SEARCH_GITINGEST",
            args="another query",
            content="https://github.com/user3/repo3\nhttps://github.com/user4/repo4"
        )
        tool2 = SearchGitingestTool(tag_without_codeblock)
        @test length(tool2.urls) == 2
        @test tool2.urls[1] == "https://github.com/user3/repo3"
        @test tool2.urls[2] == "https://github.com/user4/repo4"
    end
end
