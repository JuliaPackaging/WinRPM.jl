using WinRPM
using Test

@testset "WinRPM.jl" begin
    @testset "WinRPM.update" begin
        for (ignorecache, allow_remote) in [(false, true), (true, true)]
            WinRPM.update(ignorecache, allow_remote)
        end
    end

    if Sys.iswindows() && lowercase(get(ENV, "CI", "")) == "true"
        @testset "WinRPM.install" begin
            WinRPM.update()
            pkg = "bzip2"
            @info("Attempting to install $(pkg)")
            WinRPM.install(pkg; yes = true)
            @test isfile(WinRPM.installedlist)
            installedlist = read(WinRPM.installedlist, String)
            @test occursin(pkg, installedlist)
            @info("Successfully installed $(pkg)")
        end
    end
end
