using OpenCacheLayer
using OpenContentBroker
using OpenContentBroker: GmailAdapter, GmailSenderAdapter, send_gmail
using DotEnv
using Dates

# Load environment variables from .env
DotEnv.load!()

# Create adapters
gmail = GmailAdapter()
sender = GmailSenderAdapter(gmail)

# Get latest messages from the last hour
messages = get_content(gmail; from=now()-Hour(10))

if isempty(messages)
    println("No messages found in the last hour!")
else
    # Get the latest message
    latest = last(messages)  # messages are sorted by date
    @show latest.message_id
    
    println("\nReplying to:")
    println("From: ", latest.from)
    println("Subject: ", latest.subject)
    println("Message ID: ", latest.message_id)
    println("Original message: ", latest.body[1:min(100, length(latest.body))], "...")
    
    # Example: Reply using send_gmail with in_reply_to
    response = send_gmail(sender;
        to="havliktomi@gmail.com",
        subject=latest.subject,  # Re: will be added automatically
        body="Hi,\n\nThanks for your email!",
        in_reply_to=latest.message_id
    )
    
    println("\nReply sent successfully!")
    println("Message ID: ", response.id)
end
