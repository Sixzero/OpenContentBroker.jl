using Test
using EasyContext
using UUIDs
using ToolCallFormat: ParsedCall, ParsedValue, CodeBlock, create_tool
using OpenContentBroker: GoogleSearchTool, WebContentTool, GmailSenderTool, SearchGitingestTool

@testset failfast=true "Tool creation with ParsedCall" begin
    @testset "GoogleSearchTool creation" begin
        call = ParsedCall(
            name="google_search",
            kwargs=Dict("query" => ParsedValue("python cli tutorial"))
        )
        tool = create_tool(GoogleSearchTool, call)
        @test tool.query == "python cli tutorial"
    end

    @testset "WebContentTool creation" begin
        call = ParsedCall(
            name="read_url",
            kwargs=Dict("url" => ParsedValue("https://example.com/doc"))
        )
        tool = create_tool(WebContentTool, call)
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
        tool = create_tool(GmailSenderTool, call)
        @test tool.content isa CodeBlock
        @test contains(tool.content.content, "To: test@example.com")
        @test contains(tool.content.content, "Subject: Test Subject")
    end

    @testset "SearchGitingestTool URL parsing" begin
        # Test with code block format
        call_with_codeblock = ParsedCall(
            name="search_gitingest",
            kwargs=Dict("query" => ParsedValue("test query")),
            content="```urls\nhttps://github.com/user1/repo1\nhttps://github.com/user2/repo2\n```"
        )
        tool = create_tool(SearchGitingestTool, call_with_codeblock)
        @test tool.query == "test query"
        @test tool.urls isa CodeBlock
    end
end
