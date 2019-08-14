using Base.CoreLogging
using Test
using WinRPM

@testset "WinRPM" begin
    @testset "download(); 200" begin
        uri = "https://raw.githubusercontent.com/JuliaPackaging/WinRPM.jl/v0.4.2/sources.list"
        expected = [
            "https://cache.julialang.org/http://download.opensuse.org/repositories/windows:/mingw:/win32/openSUSE_Leap_42.2",
            "https://cache.julialang.org/http://download.opensuse.org/repositories/windows:/mingw:/win64/openSUSE_Leap_42.2",
            "",
        ]
        content, code = WinRPM.download(uri)
        @test code == 200
        actual = split(content, "\n")
        @test length(actual) == length(expected)
        for i = 1:length(actual)
            @test (i, actual[i]) == (i, expected[i])
        end
    end

    @testset "download(); 404" begin
        uri = "https://raw.githubusercontent.com/JuliaPackaging/WinRPM.jl/v0.4.2/no_such_file"
        content, code = "!", -1
        with_logger(NullLogger()) do
            content, code = WinRPM.download(uri)
        end
        #@test code == 404  # URLDownloadToCacheFileW version does not return this properly
        @test content == ""
    end
end
