using WinRPM
WinRPM.update()

# update julia's gcc dlls
@windows_only begin
    dlls = ["libgfortran-3", "libquadmath-0", "libstdc++-6", "libssp-0",
        WORD_SIZE==32 ? "libgcc_s_sjlj-1" : "libgcc_s_seh-1"]
    dlls_to_update = ASCIIString[]
    for lib in dlls
        if !isfile(joinpath(JULIA_HOME, lib * "-copy.dll"))
            push!(dlls_to_update, lib)
        end
    end
    if !isempty(dlls_to_update)
        try
            WinRPM.install(ASCIIString[replace(lib, "-", "") for lib in dlls_to_update]; yes = true)
            for lib in dlls_to_update
                mv(joinpath(JULIA_HOME, lib * ".dll"), joinpath(JULIA_HOME, lib * "-copy.dll"))
                cp(joinpath(WinRPM.installdir, "usr", Sys.MACHINE, "sys-root", "mingw", "bin", lib * ".dll"),
                    joinpath(JULIA_HOME, lib * ".dll"))
            end
            info("Updated Julia's gcc dlls, you may need to restart Julia for some WinRPM packages to work.")
        catch
            warn("Could not update Julia's gcc dlls, some WinRPM packages may not work.\n" *
                "Try running Julia as administrator and calling `Pkg.build(\"WinRPM\")`")
        end
    end
end
