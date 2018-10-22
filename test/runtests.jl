using Test
using WinRPM
using Libz, LibExpat

#check that a file with a special char is downloaded correctly
@testset "escaping" begin
    testPkgs = WinRPM.Package[]
    push!(testPkgs, WinRPM.select(WinRPM.lookup("libstdc++6", WinRPM.OS_ARCH), "libstdc++6"))
    WinRPM.do_install(WinRPM.Packages(testPkgs))
    todo, toup = WinRPM.prepare_install(testPkgs[1])
    @test( isempty(todo) && isempty(toup))
    @test true
end
