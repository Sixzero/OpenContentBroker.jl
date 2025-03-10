using OpenContentBroker
using OpenContentBroker: send_gmail
using DotEnv
using Dates

# Load environment variables from .env
DotEnv.load!()

# Create sender adapter instance with specific email
sender = GmailSenderAdapter()

# Send email with default confirmation
result = send_gmail(sender;
    to="havliktomi@gmail.com",
    subject="Test Email from Gmail Sender",
    body="""
    Hello!

    This is a test email sent from the GmailSenderAdapter.
    Current time: $(now())

    Best regards,
    Julia Gmail Sender
    """
)
println("\nEmail sent successfully!")
println("Message ID: ", result.id)
#%%
ENV["DEFAULT_GMAIL"]