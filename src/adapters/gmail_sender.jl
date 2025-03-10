using HTTP
using JSON3
using Base64
using OpenCacheLayer
using UUIDs

"""
Adapter for sending Gmail messages
"""
@kwdef struct GmailSenderAdapter <: OpenCacheLayer.ChatsLikeAdapter
    gmail_adapter::GmailAdapter=GmailAdapter()
end

"""
Send an email through Gmail with optional confirmation
"""
function send_gmail(adapter::GmailSenderAdapter;
    to::Union{String,Vector{String}},
    subject::String,
    body::String,
    from::String="",  # Optional, uses authenticated user's email if empty
    cc::Union{String,Vector{String},Nothing}=nothing,
    bcc::Union{String,Vector{String},Nothing}=nothing,
    reply_to::Union{String,Nothing}=nothing,
    in_reply_to::Union{String,Nothing}=nothing,
    references::Union{String,Nothing}=nothing,
    message_id::String=string('<', uuid4(), '@', split(adapter.gmail_adapter.email, '@')[2], '>'),
    confirm::Bool=true  # Add confirmation flag
)
    # If in_reply_to is provided, fetch original message and format as reply
    full_body = if !isnothing(in_reply_to)
        original_msg = get_message(adapter.gmail_adapter, in_reply_to)
        # Add Re: to subject if not already present
        subject = startswith(subject, r"Re:\s*"i) ? subject : "Re: $(original_msg.subject)"
        # Format quoted reply
        """
        $body

        On $(Dates.format(original_msg.date, "e, d u Y HH:MM:SS")) $(original_msg.from) wrote:
        $(join(map(line -> "> " * line, split(original_msg.body, '\n')), "\n"))
        """
    else
        body
    end
    
    # Convert to arrays if single recipient
    recipients = to isa String ? [to] : to
    cc_list = isnothing(cc) ? String[] : (cc isa String ? [cc] : cc)
    bcc_list = isnothing(bcc) ? String[] : (bcc isa String ? [bcc] : bcc)
    sender = isempty(from) ? adapter.gmail_adapter.email : from
    
    if confirm
        response = get_user_confirmation()
        println()
        @show response
        
        if !response
            @info "Email sending cancelled"
            return
        end
    end
    
    access_token = ensure_token!(adapter.gmail_adapter)
    
    # Create email message with headers and explicit UTF-8 encoding
    headers = [
        "MIME-Version: 1.0",
        "Content-Type: text/plain; charset=UTF-8",
        "Content-Transfer-Encoding: base64",
        "From: $sender",
        "To: $(join(recipients, ", "))",
        "Subject: =?UTF-8?B?$(base64encode(subject))?=",
        "Message-ID: $message_id"
    ]
    !isempty(cc_list) && push!(headers, "Cc: $(join(cc_list, ", "))")
    !isempty(bcc_list) && push!(headers, "Bcc: $(join(bcc_list, ", "))")
    !isnothing(reply_to) && push!(headers, "Reply-To: $reply_to")
    !isnothing(in_reply_to) && push!(headers, "In-Reply-To: $in_reply_to")
    !isnothing(references) && push!(headers, "References: $references")
    
    # Ensure UTF-8 encoding for the entire message
    message = String(transcode(UInt8, join([join(headers, "\n"), "", full_body], "\n")))
    
    # Encode to base64url
    encoded_message = base64encode(message)
    
    # Send request
    response = HTTP.post(
        "$GMAIL_API_BASE/users/me/messages/send",
        ["Authorization" => "Bearer $access_token",
         "Content-Type" => "application/json"],
        JSON3.write(Dict("raw" => encoded_message))
    )
    
    JSON3.read(response.body)
end

"""
Forward a message to new recipients
"""
function forward_message(adapter::GmailSenderAdapter, msg_or_id::Union{String,GmailMessage}, 
    to::Union{String,Vector{String}}; 
    extra_body::String="", 
    kwargs...
)
    # Get the message if ID was provided
    msg = msg_or_id isa String ? get_message(adapter.gmail_adapter, msg_or_id) : msg_or_id
    
    # Prepare forwarded subject
    subject = startswith(msg.subject, r"Fwd:\s*"i) ? msg.subject : "Fwd: $(msg.subject)"
    
    # Format the forwarded message
    forwarded_content = """
    $extra_body
    
    ---------- Forwarded message ---------
    From: $(msg.from)
    Date: $(Dates.format(msg.date, "e, d u Y HH:MM:SS"))
    Subject: $(msg.subject)
    To: $(join(msg.to, ", "))
    
    $(msg.body)
    """
    
    send_gmail(adapter;
        to=to,
        subject=subject,
        body=forwarded_content,
        kwargs...
    )
end

"""
Reply to all messages in a thread
"""
function reply_to_thread(adapter::GmailSenderAdapter, thread_id::String, body::String; kwargs...)
    # Get all messages in thread
    messages = get_thread_messages(adapter.gmail_adapter, thread_id)
    isempty(messages) && error("No messages found in thread")
    
    # Use the last message for reply
    last_msg = last(messages)
    
    # Include all unique participants from the thread
    all_participants = unique(vcat([m.from for m in messages], [to for m in messages for to in m.to]))
    # Remove the current sender
    filter!(e -> e != adapter.gmail_adapter.email, all_participants)
    
    # Use send_gmail directly with in_reply_to
    send_gmail(adapter;
        to=all_participants,
        subject=last_msg.subject,  # send_gmail will handle Re: prefix
        body=body,
        in_reply_to=last_msg.message_id,
        references=thread_id,
        kwargs...
    )
end

# Delegate authentication methods to the wrapped adapter
authorize!(adapter::GmailSenderAdapter) = authorize!(adapter.gmail_adapter)
force_authorize!(adapter::GmailSenderAdapter) = force_authorize!(adapter.gmail_adapter)
