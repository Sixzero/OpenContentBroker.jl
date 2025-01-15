using Base64

@testset "GmailAdapter" begin
    credentials = Dict(
        "client_id" => "mock_client_id",
        "client_secret" => "mock_client_secret",
        "refresh_token" => "mock_refresh_token"
    )
    
    adapter = GmailAdapter(credentials)
    
    @testset "Basic functionality" begin
        # Test getting new content
        messages = get_new_content(adapter)
        @test length(messages) == 1
        @test messages[1] isa AbstractMessage
        @test messages[1].processed_content isa GmailMessage
        
        
        # Test message structure
        msg = messages[1].processed_content
        @test msg.subject == "Test Email"
        @test msg.from == "sender@example.com"
        @test msg.to == ["recipient@example.com"]
        @test msg.body == "This is a test email body."
    end
    
    @testset "Raw message processing" begin
        mock_data = Dict(
            "id" => "test123",
            "threadId" => "thread123",
            "labelIds" => ["INBOX"],
            "payload" => Dict(
                "headers" => [
                    Dict("name" => "Subject", "value" => "Test Subject"),
                    Dict("name" => "From", "value" => "test@example.com"),
                    Dict("name" => "To", "value" => "recv@example.com")
                ],
                "body" => Dict(
                    "data" => base64encode("Test body content")
                )
            )
        )
        
        raw = Vector{UInt8}(JSON3.write(mock_data))
        processed = process_raw(adapter, raw)
        
        @test processed.subject == "Test Subject"
        @test processed.from == "test@example.com"
        @test processed.to == ["recv@example.com"]
        @test processed.body == "Test body content"
    end
end
