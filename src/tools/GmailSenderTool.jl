using OpenCacheLayer: get_content
using ToolCallFormat: ParsedCall
import EasyContext
using JSON3

@kwdef mutable struct GmailSenderTool <: AbstractTool
    id::UUID = uuid4()
    gmail_sender::GmailSenderAdapter = GmailSenderAdapter()
    last_response::Union{Nothing,JSON3.Object} = nothing
    cmd::String = ""  # Add command storage
end

function EasyContext.create_tool(::Type{GmailSenderTool}, call::ParsedCall)
    GmailSenderTool(cmd=call.content)
end

"""
Parse email command format:
To: recipient@email.com
Subject: Email Subject
Cc: cc@email.com  # Optional
Bcc: bcc@email.com  # Optional
In-Reply-To: <message-id>  # Optional - Reference specific message
References: <thread-id>  # Optional - Reference email thread
Message-ID: <message-id>  # Optional - Set custom message ID

Email body content here
Multiple lines are supported
"""
function parse_email_command(cmd::String)
    # Split header and body
    parts = split(cmd, "\n\n"; limit=2)
    length(parts) == 2 || error("Email must have headers and body separated by blank line")
    headers, body = parts
    
    # Parse headers
    result = Dict{String,String}()
    for line in split(headers, '\n')
        startswith(line, r"(To|Subject|Cc|Bcc|Message-ID|In-Reply-To|References):") || continue
        key, value = split(line, ":", limit=2)
        result[lowercase(replace(key, "-" => "_"))] = strip(value)
    end
    
    # Validate required fields
    haskey(result, "to") || error("Missing To: header")
    haskey(result, "subject") || error("Missing Subject: header")
    
    result["body"] = strip(body)
    result
end

# Change execute to use stored command
function EasyContext.execute(tool::GmailSenderTool; no_confirm::Bool=false)
    # Parse command
    email_params = parse_email_command(tool.cmd)
    
    # Send email with all optional parameters
    tool.last_response = send_gmail(tool.gmail_sender;
        to=email_params["to"],
        subject=email_params["subject"],
        body=email_params["body"],
        cc=get(email_params, "cc", nothing),
        bcc=get(email_params, "bcc", nothing),
        reply_to=get(email_params, "reply_to", nothing),
        in_reply_to=get(email_params, "in_reply_to", nothing),
        references=get(email_params, "references", nothing)
    )
end

# Tool interface implementations
EasyContext.toolname(::Type{GmailSenderTool}) = "gmail_send"
const GMAIL_SEND_SCHEMA = (
    name = "gmail_send",
    description = "Send an email via Gmail",
    params = [
        (name = "to", type = "string", description = "Recipient email address", required = true),
        (name = "subject", type = "string", description = "Email subject", required = true),
        (name = "body", type = "string", description = "Email body content", required = true),
        (name = "cc", type = "string", description = "CC address", required = false),
        (name = "bcc", type = "string", description = "BCC address", required = false)
    ]
)
EasyContext.get_tool_schema(::Type{GmailSenderTool}) = GMAIL_SEND_SCHEMA
EasyContext.get_description(::Type{GmailSenderTool}) = EasyContext.description_from_schema(GMAIL_SEND_SCHEMA)
# TODO why do we need "don't retry", it should be obvious.
EasyContext.result2string(tool::GmailSenderTool)::String = 
    isnothing(tool.last_response) ? "No email send got cancelled, don't retry." :
    "Email sent successfully. Message ID: $(tool.last_response.id)"
EasyContext.tool_format(::Type{GmailSenderTool}) = :multi_line
