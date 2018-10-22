using Test
using WinRPM
using Libz, LibExpat

#check that a file with a special char is downloaded correctly
@testset "escaping" begin
    pkgs = [WinRPM.select(WinRPM.lookup("libstdc++6", WinRPM.OS_ARCH), "libstdc++6"))]
    WinRPM.do_install(WinRPM.Packages(pkgs))
    todo, toup = WinRPM.prepare_install(pkgs[1])
    @test isempty(todo) && isempty(toup)
end
