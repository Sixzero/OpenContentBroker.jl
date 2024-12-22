using OpenContentBroker
using Test
using Aqua
using Dates
using Base64
using JSON3

include("gmail_adapter.jl")

@testset "OpenContentBroker.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(OpenContentBroker)
    end

end
