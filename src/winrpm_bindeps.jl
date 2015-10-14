# BinDeps integration

using BinDeps
import BinDeps: PackageManager, can_use, package_available, available_version, libdir, generate_steps, LibraryDependency, provider, pkg_name

update_once = true

type RPM <: PackageManager 
    package
end

can_use(::Type{RPM}) = OS_NAME == :Windows
function package_available(p::RPM) 
    global update_once::Bool
    !can_use(RPM) && return false    
    pkgs = p.package
    if isa(pkgs,AbstractString)
        pkgs = [pkgs]
    end
    if (update_once::Bool) 
        info("Updating WinRPM package list")
        update(); update_once = false;
    end
    return all(pkg->(length(lookup(pkg).p) > 0),pkgs)
end

available_version(p::RPM) = lookup(p.package).p[1][xpath"version/@ver"][1]
libdir(p::RPM,dep) = joinpath(dirname(dirname(@__FILE__)),"deps","usr","$(Sys.ARCH)-w64-mingw32","sys-root","mingw","bin")
pkg_name(p::RPM) = p.package

provider(::Type{RPM},packages::Vector{ASCIIString}; opts...) = RPM(packages)

function generate_steps(dep::LibraryDependency,h::RPM,opts) 
    if get(opts,:force_rebuild,false) 
        error("Will not force WinRPM to rebuild dependency \"$(dep.name)\".\n"*
              "Please make any necessary adjustments manually (This might just be a version upgrade)")
    end
    ()->install(h.package; yes = true)
end
