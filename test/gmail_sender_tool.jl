using Test
using OpenContentBroker: GmailSenderTool, parse_email_command
using EasyContext: ToolTag, parse_raw_block

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
        with múltiple lines
        and some špećial characters.
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
        with múltiple lines
        and some špećial characters."""
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

    @testset "Tool instantiation" begin
        cmd = """
        To: test@example.com
        Subject: Test Email

        Test body
        """
        # Use the kwdef constructor instead
        tool_tag = ToolTag(name="GMAIL_SEND", content=cmd, args="", kwargs=Dict{String,String}())
        tool = GmailSenderTool(cmd=parse_raw_block(tool_tag.content))
        
        @test tool.cmd == cmd
        @test isnothing(tool.last_response)
    end
end
