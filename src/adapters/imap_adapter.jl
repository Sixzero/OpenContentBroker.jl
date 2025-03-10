using Base64
using Dates
using OpenCacheLayer
using PyCall
using Unicode

# Lazy load Python modules
const imaplib = Ref{PyObject}()
const email = Ref{PyObject}()
const imapclient = Ref{PyObject}()

function ensure_py_modules()
    if !isdefined(imaplib, :x)
        imaplib[] = pyimport("imaplib")
        email[] = pyimport("email")
        imapclient[] = pyimport("imapclient")
    end
end

@kwdef struct IMAPConfig
    host::String
    port::Int
    username::String
    password::String
    use_ssl::Bool = true
end

mutable struct IMAPAdapter <: OpenCacheLayer.ChatsLikeAdapter
    config::IMAPConfig
    connection::Union{Nothing, PyObject}
end
# Constructor with default nothing for connection
IMAPAdapter(config::IMAPConfig) = IMAPAdapter(config, nothing)

struct IMAPMessage <: OpenCacheLayer.AbstractMessage
    subject::String
    body::String
    from::String
    to::Vector{String}
    message_id::String
    date::DateTime
    raw_content::Vector{UInt8}
    references::Vector{String}
    in_reply_to::Union{String,Nothing}
end

function IMAPAdapter(;
    host::String,
    port::Int=993,
    username::String,
    password::String,
    use_ssl::Bool=true
)
    config = IMAPConfig(host=host, port=port, username=username, password=password, use_ssl=use_ssl)
    IMAPAdapter(config)
end

function ensure_connection!(adapter::IMAPAdapter)
    ensure_py_modules()  # Ensure Python modules are loaded
    if isnothing(adapter.connection)
        adapter.connection = adapter.config.use_ssl ? 
            imaplib[].IMAP4_SSL(adapter.config.host, adapter.config.port) :
            imaplib[].IMAP4(adapter.config.host, adapter.config.port)
        
        adapter.connection.login(adapter.config.username, adapter.config.password)
    end
    adapter.connection
end

function process_raw(adapter::IMAPAdapter, raw::Vector{UInt8})
    ensure_py_modules()  # Ensure Python modules are loaded
    msg_data = email[].message_from_bytes(raw)
    
    # Extract body considering multipart messages
    function get_body(msg)
        if msg.is_multipart()
            for part in msg.walk()
                ctype = part.get_content_type()
                if ctype == "text/plain"
                    return String(part.get_payload(decode=true))
                end
            end
            return ""
        else
            return String(msg.get_payload(decode=true))
        end
    end

    IMAPMessage(
        msg_data.get("Subject", ""),
        get_body(msg_data),
        msg_data.get("From", ""),
        split(msg_data.get("To", ""), ","),
        msg_data.get("Message-ID", ""),
        try
            DateTime(msg_data.get("Date", ""))
        catch
            now()
        end,
        raw,
        split(msg_data.get("References", ""), " "),
        msg_data.get("In-Reply-To", nothing)
    )
end

function OpenCacheLayer.get_content(adapter::IMAPAdapter;
    from::DateTime=now() - Day(1),
    to::Union{DateTime,Nothing}=nothing,
    max_results::Int=100,
    folder::String="INBOX"
)
    conn = ensure_connection!(adapter)
    
    # Select folder
    conn.select(folder)
    
    # Build IMAP search query with proper date format
    # IMAP requires dates in DD-Mon-YYYY format where Mon is in English
    date_format(dt) = uppercase(Dates.format(dt, "d-u-Y"))
    
    query = ["ALL"]
    push!(query, "SINCE $(date_format(from))")
    if !isnothing(to)
        push!(query, "BEFORE $(date_format(to))")
    end
    
    # Search messages
    typ, message_nums = conn.search(nothing, join(query, " "))
    message_ids = split(String(message_nums[1]))
    
    # Fetch messages
    messages = IMAPMessage[]
    for id in message_ids[1:min(length(message_ids), max_results)]
        typ, msg_data = conn.fetch(id, "(RFC822)")
        email_body = msg_data[1][2]  # Get the email body
        push!(messages, process_raw(adapter, Vector{UInt8}(email_body)))
    end
    
    sort!(messages, by = x -> x.date)
    messages
end

OpenCacheLayer.supports_time_range(::IMAPAdapter) = true

function OpenCacheLayer.get_timestamp(message::IMAPMessage)
    message.date
end

function OpenCacheLayer.get_unique_id(message::IMAPMessage)
    message.message_id
end

"""
    list_folders(adapter::IMAPAdapter)

Lists available IMAP folders with proper UTF-8 decoding.
"""
function list_folders(adapter::IMAPAdapter)
    ensure_py_modules()  # Ensure Python modules are loaded
    conn = ensure_connection!(adapter)
    typ, data = conn.list()
    return map(data) do d
        parts = split(String(d), "\"")
        encoded = length(parts) > 2 ? String(parts[end][2:end]) : String(parts[end])
        try
            cleaned = replace(encoded, r"^\s*\/?\s*" => "")
            decoded = imapclient[].imap_utf7.decode(cleaned)
            String(transcode(String, Vector{UInt8}(decoded)))
        catch
            try
                String(transcode(String, Vector{UInt8}(encoded)))
            catch
                encoded
            end
        end
    end |> unique
end

"""
    create_folder(adapter::IMAPAdapter, folder_name::String)

Creates a new IMAP folder with the given name if it doesn't exist already.
"""
function create_folder(adapter::IMAPAdapter, folder_name::String)
    ensure_py_modules()  # Ensure Python modules are loaded
    existing_folders = list_folders(adapter)
    normalized_name = Unicode.normalize(folder_name, :NFC)
    if any(f -> Unicode.normalize(f, :NFC) == normalized_name, existing_folders)
        @info "Folder already exists: $folder_name"
        return true
    end
    
    conn = ensure_connection!(adapter)
    try
        encoded_name = imapclient[].imap_utf7.encode(folder_name)
        conn.create(encoded_name)
        return true
    catch e
        @warn "Failed to create folder: $folder_name" exception=e
        return false
    end
end

"""
    move_message(adapter::IMAPAdapter, message::IMAPMessage, target_folder::String)

Áthelyez egy üzenetet a megadott célmappába.
"""
function move_message(adapter::IMAPAdapter, message::IMAPMessage, target_folder::String)
    conn = ensure_connection!(adapter)
    
    # Keressük meg az üzenet UID-ját
    conn.select("INBOX")
    typ, data = conn.search(nothing, "HEADER Message-ID $(message.message_id)")
    message_nums = split(String(data[1]))
    
    if isempty(message_nums)
        @warn "Nem található az üzenet: $(message.message_id)"
        return false
    end
    
    # Üzenet áthelyezése
    try
        conn.copy(message_nums[1], target_folder)
        conn.store(message_nums[1], "+FLAGS", "\\Deleted")
        conn.expunge()
        return true
    catch e
        @warn "Nem sikerült áthelyezni az üzenetet" exception=e
        return false
    end
end
