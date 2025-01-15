using BaseDirs

abstract type TokenStorage end

"""
FileStorage that uses BaseDirs to store tokens in specific files
"""
struct FileStorage <: TokenStorage
    project::BaseDirs.Project
end

FileStorage(name::AbstractString) = FileStorage(BaseDirs.Project(name))

function get_token_path(storage::FileStorage; filename::String="tokens.env")
    BaseDirs.User.config(storage.project, filename; create=true)
end

function get_token(storage::FileStorage; filename::String="tokens.env")
    token_path = get_token_path(storage; filename)
    !isfile(token_path) && return nothing
    
    for line in eachline(token_path)
        k, v = split(line, "=", limit=2)
        k == "REFRESH_TOKEN" && return v
    end
    nothing
end

function store_token!(storage::FileStorage, value::String; filename::String="tokens.env")
    token_path = get_token_path(storage; filename)
    open(token_path, "w") do io
        println(io, "REFRESH_TOKEN=$value")
    end
end
