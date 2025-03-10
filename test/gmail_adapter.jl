using Base64
using Test
using OpenContentBroker
using OpenContentBroker: GmailAdapter, GmailMessage, process_raw
using OpenCacheLayer: get_content
using JSON3
using Dates

@testset "GmailAdapter" begin
    # Setup test environment
    # ENV["GMAIL_CLIENT_ID"] = "test_client_id"
    # ENV["GMAIL_CLIENT_SECRET"] = "test_client_secret"
    # ENV["GMAIL_EMAIL"] = "test@example.com"
    
    # @testset "Constructor" begin
    #     adapter = GmailAdapter()
    #     @test adapter.email == "test@example.com"
        
    #     # Test with explicit credentials
    #     credentials = Dict(
    #         "client_id" => "custom_id",
    #         "client_secret" => "custom_secret"
    #     )
    #     adapter_custom = GmailAdapter(credentials, "custom@example.com")
    #     @test adapter_custom.email == "custom@example.com"
    # end

    @testset "Basic functionality" begin
        adapter = GmailAdapter()
        # Test getting new content
        messages = get_content(adapter)
        @test messages[1] isa GmailMessage
        
        # Test message structure
        msg = messages[1]
        @test msg.body isa String
    end

    @testset "Raw message processing" begin
        adapter = GmailAdapter()
        
        # Create a realistic Gmail-like message structure
        mock_data = Dict(
            "id" => "msg123",
            "threadId" => "thread123",
            "labelIds" => ["INBOX", "UNREAD"],
            "internalDate" => "$(floor(Int, datetime2unix(now()) * 1000))",
            "payload" => Dict(
                "headers" => [
                    Dict("name" => "Subject", "value" => "Test Subject"),
                    Dict("name" => "From", "value" => "sender@example.com"),
                    Dict("name" => "To", "value" => "recipient@example.com"),
                    Dict("name" => "Date", "value" => "Thu, 1 Jan 2024 10:00:00 +0000"),
                    Dict("name" => "References", "value" => "<ref1@example.com> <ref2@example.com>"),
                    Dict("name" => "In-Reply-To", "value" => "<parent@example.com>")
                ],
                "mimeType" => "text/plain",
                "body" => Dict(
                    "data" => base64encode("Test email content")
                )
            )
        )
        
        raw = Vector{UInt8}(JSON3.write(mock_data))
        msg = process_raw(adapter, raw)
        
        @test msg isa GmailMessage
        @test msg.subject == "Test Subject"
        @test msg.from == "sender@example.com"
        @test msg.to == ["recipient@example.com"]
        @test msg.body == "Test email content"
        @test msg.message_id == "msg123"
        @test msg.thread_id == "thread123"
        @test "INBOX" in msg.labels
        @test length(msg.references) == 3  # 2 refs + 1 in-reply-to
        @test msg.in_reply_to == "<parent@example.com>"
    end
    
    @testset "MIME multipart handling" begin
        adapter = GmailAdapter()
        
        # Test multipart message with text/plain preference
        multipart_data = Dict(
            "id" => "msg456",
            "threadId" => "thread456",
            "labelIds" => ["INBOX"],
            "internalDate" => "$(floor(Int, datetime2unix(now()) * 1000))",
            "payload" => Dict(
                "headers" => [
                    Dict("name" => "Subject", "value" => "Multipart Test"),
                    Dict("name" => "From", "value" => "sender@example.com"),
                    Dict("name" => "To", "value" => "recipient@example.com")
                ],
                "mimeType" => "multipart/alternative",
                "parts" => [
                    Dict(
                        "mimeType" => "text/html",
                        "body" => Dict("data" => base64encode("<html>HTML content</html>"))
                    ),
                    Dict(
                        "mimeType" => "text/plain",
                        "body" => Dict("data" => base64encode("Plain text content"))
                    )
                ]
            )
        )
        
        raw = Vector{UInt8}(JSON3.write(multipart_data))
        msg = process_raw(adapter, raw)
        
        @test msg.body == "Plain text content"  # Should prefer text/plain
    end
end
