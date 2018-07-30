@static if VERSION < v"0.7.0-DEV.914" ? is_windows() : Sys.iswindows()
    using WinRPM
    WinRPM.update()
end
