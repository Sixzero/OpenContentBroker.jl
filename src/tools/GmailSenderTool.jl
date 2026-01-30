using JSON3

# Lazy-initialized adapter (avoid precompile failures from missing credentials)
const _GMAIL_SENDER_ADAPTER = Ref{Union{GmailSenderAdapter, Nothing}}(nothing)
get_gmail_sender_adapter() = (_GMAIL_SENDER_ADAPTER[] === nothing && (_GMAIL_SENDER_ADAPTER[] = GmailSenderAdapter()); _GMAIL_SENDER_ADAPTER[])

"""
Parse email command format:
To: recipient@email.com
Subject: Email Subject
Cc: cc@example.com  # Optional
Bcc: bcc@example.com  # Optional
In-Reply-To: <message-id>  # Optional
References: <thread-id>  # Optional

Email body content here
"""
function parse_email_command(cmd::String)
    parts = split(cmd, "\n\n"; limit=2)
    length(parts) == 2 || error("Email must have headers and body separated by blank line")
    headers, body = parts

    result = Dict{String,String}()
    for line in split(headers, '\n')
        startswith(line, r"(To|Subject|Cc|Bcc|Message-ID|In-Reply-To|References):") || continue
        key, value = split(line, ":", limit=2)
        result[lowercase(replace(key, "-" => "_"))] = strip(value)
    end

    haskey(result, "to") || error("Missing To: header")
    haskey(result, "subject") || error("Missing Subject: header")

    result["body"] = strip(body)
    result
end

using ToolCallFormat: @deftool, CodeBlock

@deftool "Send an email via Gmail" function gmail_send("Email in headers+body format" => content::CodeBlock)
    email_params = parse_email_command(string(content))

    response = send_gmail(get_gmail_sender_adapter();
        to=email_params["to"],
        subject=email_params["subject"],
        body=email_params["body"],
        cc=get(email_params, "cc", nothing),
        bcc=get(email_params, "bcc", nothing),
        reply_to=get(email_params, "reply_to", nothing),
        in_reply_to=get(email_params, "in_reply_to", nothing),
        references=get(email_params, "references", nothing)
    )

    isnothing(response) ? "No email sent, cancelled." : "Email sent successfully. Message ID: $(response.id)"
end

# Backward compatibility alias
const GmailSenderTool = GmailSendTool
