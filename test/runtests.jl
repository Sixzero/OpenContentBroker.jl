using OpenContentBroker
using Test
using Aqua

@testset "OpenContentBroker.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(OpenContentBroker)
    end
    # Write your tests here.
end
