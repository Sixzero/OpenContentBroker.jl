using Test
using OpenContentBroker: GmailSenderTool, parse_email_command
using ToolCallFormat: ParsedCall, create_tool

@testset "GmailSenderTool Tests" begin
    @testset "parse_email_command" begin
        email_cmd = """
        To: test@example.com
        Subject: Test Email
        Cc: cc@example.com
        Bcc: bcc@example.com
        In-Reply-To: <abc123@mail.com>
        References: <thread123@mail.com>

        Hello World!
        This is a test email
        with multiple lines
        and some special characters.
        """

        result = parse_email_command(email_cmd)

        @test result["to"] == "test@example.com"
        @test result["subject"] == "Test Email"
        @test result["cc"] == "cc@example.com"
        @test result["bcc"] == "bcc@example.com"
        @test result["in_reply_to"] == "<abc123@mail.com>"
        @test result["references"] == "<thread123@mail.com>"
        @test result["body"] == """Hello World!
        This is a test email
        with multiple lines
        and some special characters."""
    end

    @testset "parse_email_command validation" begin
        # Missing required fields
        @test_throws ErrorException parse_email_command("""
        To: test@example.com

        Body only
        """)

        @test_throws ErrorException parse_email_command("""
        Subject: Test

        Body only
        """)

        # Missing body separator
        @test_throws ErrorException parse_email_command("To: test@example.com\nSubject: Test\nBody")
    end

    @testset "Tool instantiation with ParsedCall" begin
        cmd = """To: test@example.com
Subject: Test Email

Test body"""

        call = ParsedCall(name="gmail_send", content=cmd)
        tool = create_tool(GmailSenderTool, call)

        @test tool.content isa String
        @test tool.content.content == cmd
    end
end
