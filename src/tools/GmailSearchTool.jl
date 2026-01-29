using Dates: DateTime, now, Day
using ToolCallFormat: @deftool

# Module-level defaults
const GMAIL_SEARCH_ADAPTER = GmailAdapter()
const GMAIL_SEARCH_PIPELINE = EFFICIENT_PIPELINE()

@deftool "Search relevant emails for a query" function gmail_search(query::String => "Email search query")
    # Get emails
    emails = get_content(GMAIL_SEARCH_ADAPTER; from=now() - Day(7), max_results=100, labels=["INBOX"])

    if isempty(emails)
        return "No emails found matching the criteria."
    end

    # Prepare email contents for reranking
    email_texts = [
        """
        Subject: $(email.subject)
        From: $(email.from)
        Date: $(email.date)

        $(email.body)
        """ for email in emails
    ]

    println("Reranking $(length(email_texts)) emails...")
    search_results = search(GMAIL_SEARCH_PIPELINE, email_texts, query)
    result_indices = [findfirst(t -> occursin(r, t), email_texts) for r in search_results]

    results = []
    for (chunk, idx) in zip(search_results, result_indices)
        email = emails[idx]
        push!(results, """
        Email #$idx:
        Message ID: $(email.message_id)
        Thread ID: $(email.thread_id)
        Subject: $(email.subject)
        From: $(email.from)
        Date: $(email.date)

        $chunk
        """)
    end
    "Reranked email results for '$query':\n\n$(join(results, "\n" * "-"^50 * "\n"))"
end
