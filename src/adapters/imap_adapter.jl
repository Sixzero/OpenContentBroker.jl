using Base64
using Dates
using OpenCacheLayer
using PythonCall
using Unicode

# Lazy load Python modules
const _imaplib = Ref{Py}()
const _email = Ref{Py}()
const _imapclient = Ref{Py}()

function ensure_py_modules()
    if !isassigned(_imaplib)
        _imaplib[] = pyimport("imaplib")
        _email[] = pyimport("email")
        _imapclient[] = pyimport("imapclient")
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
    connection::Union{Nothing, Py}
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
            _imaplib[].IMAP4_SSL(adapter.config.host, adapter.config.port) :
            _imaplib[].IMAP4(adapter.config.host, adapter.config.port)
        
        adapter.connection.login(adapter.config.username, adapter.config.password)
    end
    adapter.connection
end

function process_raw(adapter::IMAPAdapter, raw::Vector{UInt8})
    ensure_py_modules()  # Ensure Python modules are loaded
    msg_data = _email[].message_from_bytes(pybytes(raw))

    # Extract body considering multipart messages
    function get_body(msg)
        if pyconvert(Bool, msg.is_multipart())
            for part in msg.walk()
                ctype = pyconvert(String, part.get_content_type())
                if ctype == "text/plain"
                    payload = part.get_payload(; decode=true)
                    return pyisinstance(payload, pybuiltins.bytes) ?
                        String(pyconvert(Vector{UInt8}, payload)) : ""
                end
            end
            return ""
        else
            payload = msg.get_payload(; decode=true)
            return pyisinstance(payload, pybuiltins.bytes) ?
                String(pyconvert(Vector{UInt8}, payload)) : ""
        end
    end

    subject = pyconvert(String, msg_data.get("Subject", ""))
    from_addr = pyconvert(String, msg_data.get("From", ""))
    to_addr = pyconvert(String, msg_data.get("To", ""))
    message_id = pyconvert(String, msg_data.get("Message-ID", ""))
    date_str = pyconvert(String, msg_data.get("Date", ""))
    refs = pyconvert(String, msg_data.get("References", ""))
    in_reply = msg_data.get("In-Reply-To", nothing)
    in_reply_to = pyisnone(in_reply) ? nothing : pyconvert(String, in_reply)

    IMAPMessage(
        subject,
        get_body(msg_data),
        from_addr,
        split(to_addr, ","),
        message_id,
        try
            DateTime(date_str)
        catch
            now()
        end,
        raw,
        split(refs, " "),
        in_reply_to
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
    result = conn.search(nothing, join(query, " "))
    typ = result[0]
    message_nums = result[1]
    message_ids = split(pyconvert(String, message_nums[0]))

    # Fetch messages
    messages = IMAPMessage[]
    for id in message_ids[1:min(length(message_ids), max_results)]
        result = conn.fetch(id, "(RFC822)")
        typ = result[0]
        msg_data = result[1]
        email_body = msg_data[0][1]  # Get the email body (Python uses 0-indexing)
        push!(messages, process_raw(adapter, pyconvert(Vector{UInt8}, email_body)))
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
    result = conn.list()
    typ = result[0]
    data = result[1]
    folders = String[]
    for i in 0:(pylen(data)-1)
        d = data[i]
        d_str = pyconvert(String, d)
        parts = split(d_str, "\"")
        encoded = length(parts) > 2 ? String(parts[end][2:end]) : String(parts[end])
        try
            cleaned = replace(encoded, r"^\s*\/?\s*" => "")
            decoded = _imapclient[].imap_utf7.decode(cleaned)
            push!(folders, pyconvert(String, decoded))
        catch
            try
                push!(folders, String(transcode(String, Vector{UInt8}(encoded))))
            catch
                push!(folders, encoded)
            end
        end
    end
    return unique(folders)
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
        encoded_name = _imapclient[].imap_utf7.encode(folder_name)
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
    result = conn.search(nothing, "HEADER Message-ID $(message.message_id)")
    typ = result[0]
    data = result[1]
    message_nums = split(pyconvert(String, data[0]))
    
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
