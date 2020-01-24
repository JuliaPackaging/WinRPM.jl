using WinRPM
using Test

@testset "WinRPM.jl" begin
    @testset "WinRPM.update" begin
        for (ignorecache, allow_remote) in [(false, true), (true, true)]
            WinRPM.update(ignorecache, allow_remote)
        end
    end

    if Sys.iswindows()
        @testset "WinRPM.install" begin
            WinRPM.update()
            WinRPM.install("bzip2"; yes = true)
            @test isfile(WinRPM.installedlist)
            installedlist = read(WinRPM.installedlist, String)
            @test occursin("bzip2", installedlist)
        end
    end
end
