using OpenCacheLayer
using OpenContentBroker
using Dates

# IMAP konfigurációs adatok
const IMAP_CONFIG = Dict(
    "host" => "imap.freemail.hu",  # Freemail IMAP szerver
    "port" => 993,                 # SSL port
    "username" => "havlik@freemail.hu",
    "password" => get(ENV, "IMAP_PASSWORD", "")
)

# Adapter létrehozása
imap = IMAPAdapter(;
    host = IMAP_CONFIG["host"],
    port = IMAP_CONFIG["port"],
    username = IMAP_CONFIG["username"],
    password = IMAP_CONFIG["password"]
)

# Példa 1: Utolsó 24 óra emailjeinek lekérése
println("Fetching last 24 hours of emails...")
recent_messages = get_content(imap)
println("Found $(length(recent_messages)) messages\n")

# Példa 2: Utolsó hét email keresése specifikus mappából
println("Fetching last week's emails from INBOX...")
weekly_messages = get_content(imap,
    from = now() - Day(7),
    max_results = 50,
    folder = "INBOX"
)

# Email adatok kiírása
for msg in weekly_messages
    println("=" ^ 50)
    println("Subject: $(msg.subject)")
    println("From: $(msg.from)")
    println("Date: $(msg.date)")
    println("To: $(join(msg.to, ", "))")
    println("-" ^ 20)
    println("Body preview: $(first(msg.body, 200))...")
    println()
end

# Példa 3: Specifikus időtartam keresése
println("\nFetching emails between specific dates...")
specific_messages = get_content(imap,
    from = DateTime(2024, 2, 1),
    to = DateTime(2024, 2, 29),
    max_results = 100
)
println("Found $(length(specific_messages)) messages in Február 2025")

#%%
# Mappák kezelése
println("\nMappák kezelése...")

using OpenContentBroker: list_folders, create_folder

# Reklámok mappa létrehozása (ha még nem létezik)
println("\nReklámok mappa létrehozása...")
create_folder(imap, "Reklámok")

# # Példa: reklámnak tűnő emailek áthelyezése
# println("\nReklám emailek keresése és áthelyezése...")
# for msg in recent_messages
#     # Egyszerű példa: ha a tárgy tartalmaz reklámra utaló kulcsszavakat
#     spam_keywords = ["reklám", "akció", "kedvezmény", "sale", "% off"]
#     if any(kw -> occursin(lowercase(kw), lowercase(msg.subject)), spam_keywords)
#         println("Reklámnak tűnő email találva: $(msg.subject)")
#         if move_message(imap, msg, "Reklámok")
#             println("  ✓ Áthelyezve a Reklámok mappába")
#         end
#     end
# end
#%%
# Példa 4: Kapcsolat bezárása
if !isnothing(imap.connection)
    imap.connection.logout()
end
