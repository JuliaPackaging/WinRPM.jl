using Test
using WinRPM
using   Libz, LibExpat#\, URIParser

@testset "WinRPM" begin

#check if a file with a special char is downloaded correctly
    @testset "escaping" begin
        todo = WinRPM.Package[]
        push!(todo, WinRPM.select(WinRPM.lookup("libstdc++6", WinRPM.OS_ARCH),"libstdc++6"))    #push!(todo, select(lookup(pkg, arch), pkg))
        WinRPM.do_install(WinRPM.Packages(todo))
        @test true
    end;

end;
