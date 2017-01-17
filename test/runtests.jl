using WinRPM
using Base.Test

WinRPM.install("gtk2", yes=true)
WinRPM.install("gcc", yes=true)
