using HTTP
using URIs
using JSON3

"""
OAuth2 configuration and helper functions for authentication flows.
"""
struct OAuth2Config
    auth_uri::String
    token_uri::String
    scope::String
    redirect_uri::String
    client_id::String
    client_secret::String
end

"""
Represents OAuth2 tokens returned from authorization
"""
struct OAuth2Token
    access_token::String
    refresh_token::String
    token_type::String
    expires_in::Int
end

# Convert JSON response to OAuth2Token
function OAuth2Token(data::Dict)
    OAuth2Token(
        data["access_token"],
        get(data, "refresh_token", ""),  # Optional in refresh flow
        data["token_type"],
        data["expires_in"]
    )
end

"""
    get_auth_url(config::OAuth2Config) -> String

Generate the OAuth2 authorization URL.
"""
function get_auth_url(config::OAuth2Config)
    auth_params = Dict(
        "client_id" => config.client_id,
        "redirect_uri" => config.redirect_uri,
        "scope" => config.scope,
        "response_type" => "code",
        "access_type" => "offline",
        "prompt" => "consent"
    )
    string(config.auth_uri, "?", URIs.escapeuri(auth_params))
end

"""
    exchange_code_for_tokens(config::OAuth2Config, code::String) -> OAuth2Token

Exchange authorization code for access and refresh tokens.
"""
function exchange_code_for_tokens(config::OAuth2Config, code::String)::OAuth2Token
    response = HTTP.post(
        config.token_uri,
        ["Content-Type" => "application/x-www-form-urlencoded"],
        URIs.escapeuri(Dict(
            "client_id" => config.client_id,
            "client_secret" => config.client_secret,
            "code" => code,
            "redirect_uri" => config.redirect_uri,
            "grant_type" => "authorization_code"
        ))
    )
    OAuth2Token(JSON3.read(response.body))
end

"""
    start_oauth_flow!(token_handler::Function, config::OAuth2Config) -> Nothing

Start OAuth2 authorization flow and handle the received tokens with the provided handler function.
"""
function start_oauth_flow!(token_handler::Function, config::OAuth2Config)
    auth_url = get_auth_url(config)
    println("\nOpen this URL in your browser:\n", auth_url)
    
    println("\nWaiting for authorization...")
    server = HTTP.serve("127.0.0.1", 8080) do request
        code = HTTP.queryparams(HTTP.URI(request.target))["code"]
        tokens = exchange_code_for_tokens(config, code)
        token_handler(tokens)
        
        HTTP.close(server)
        return HTTP.Response(200, "Authorization successful! You can close this window.")
    end
    
    println("\nPress Enter to exit...")
    readline()
    nothing
end

"""
    refresh_access_token(config::OAuth2Config, refresh_token::String) -> OAuth2Token

Get a new access token using a refresh token.
"""
function refresh_access_token(config::OAuth2Config, refresh_token::String)::OAuth2Token
    response = HTTP.post(
        config.token_uri,
        ["Content-Type" => "application/x-www-form-urlencoded"],
        URIs.escapeuri(Dict(
            "client_id" => config.client_id,
            "client_secret" => config.client_secret,
            "refresh_token" => refresh_token,
            "grant_type" => "refresh_token"
        ))
    )
    OAuth2Token(JSON3.read(response.body))
end
