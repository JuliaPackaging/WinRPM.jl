using WinRPM
using Test
WinRPM.install("gcc", yes = true)
gcc = joinpath(WinRPM.installdir, "usr", string(Sys.ARCH, "-w64-mingw32"), "sys-root", "mingw", "bin", "gcc.exe")

@test success(`$gcc --version`)
