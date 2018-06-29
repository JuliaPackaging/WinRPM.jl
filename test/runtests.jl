using WinRPM
using Test

if haskey(ENV, "CI") && haskey(ENV, "WINRPM_DO_THE_TEST") && ENV["WINRPM_DO_THE_TEST"] == "true"
    WinRPM.install("gcc", yes = true)
    gcc = joinpath(WinRPM.installdir, "usr", string(Sys.ARCH, "-w64-mingw32"), "sys-root", "mingw", "bin", "gcc.exe")

    @test success(`$gcc --version`)
end
