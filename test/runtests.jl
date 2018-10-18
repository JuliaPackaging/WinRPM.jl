using Test
using WinRPM
using Libz, LibExpat

#check that a file with a special char is downloaded correctly
@testset "escaping" begin
    todo = WinRPM.Package[]
    push!(todo, WinRPM.select(WinRPM.lookup("libstdc++6", WinRPM.OS_ARCH), "libstdc++6"))
    WinRPM.do_install(WinRPM.Packages(todo))
    @test true
end
