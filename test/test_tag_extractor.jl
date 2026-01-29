using Test
using EasyContext
using UUIDs
using ToolCallFormat: ParsedCall, ParsedValue
using EasyContext: AbstractTool
using OpenContentBroker: GoogleSearchTool, WebContentTool, GmailSenderTool, SearchGitingestTool

@testset failfast=true "Tool creation with ParsedCall" begin
    @testset "GoogleSearchTool creation" begin
        call = ParsedCall(
            name="google_search",
            kwargs=Dict("query" => ParsedValue("python cli tutorial"))
        )
        tool = EasyContext.create_tool(GoogleSearchTool, call)
        @test tool.query == "python cli tutorial"
    end

    @testset "WebContentTool creation" begin
        call = ParsedCall(
            name="read_url",
            kwargs=Dict("url" => ParsedValue("https://example.com/doc"))
        )
        tool = EasyContext.create_tool(WebContentTool, call)
        @test tool.url == "https://example.com/doc"
    end

    @testset "GmailSenderTool creation" begin
        content = """To: test@example.com
Subject: Test Subject
Reply-To: reply@example.com

Test email body content
Multiple lines supported"""

        call = ParsedCall(
            name="gmail_send",
            content=content
        )
        tool = EasyContext.create_tool(GmailSenderTool, call)
        @test contains(tool.cmd, "To: test@example.com")
        @test contains(tool.cmd, "Subject: Test Subject")
        @test contains(tool.cmd, "Test email body content")
    end

    @testset "SearchGitingestTool URL parsing" begin
        # Test with code block format
        call_with_codeblock = ParsedCall(
            name="search_gitingest",
            kwargs=Dict("query" => ParsedValue("test query")),
            content="```urls\nhttps://github.com/user1/repo1\nhttps://github.com/user2/repo2\n```"
        )
        tool = EasyContext.create_tool(SearchGitingestTool, call_with_codeblock)
        @test length(tool.urls) == 2
        @test tool.urls[1] == "https://github.com/user1/repo1"
        @test tool.urls[2] == "https://github.com/user2/repo2"
        @test tool.query == "test query"

        # Test with plain text format (no code block)
        call_without_codeblock = ParsedCall(
            name="search_gitingest",
            kwargs=Dict("query" => ParsedValue("another query")),
            content="https://github.com/user3/repo3\nhttps://github.com/user4/repo4"
        )
        tool2 = EasyContext.create_tool(SearchGitingestTool, call_without_codeblock)
        @test length(tool2.urls) == 2
        @test tool2.urls[1] == "https://github.com/user3/repo3"
        @test tool2.urls[2] == "https://github.com/user4/repo4"
        @test tool2.query == "another query"
    end
end
