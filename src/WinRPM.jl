__precompile__()

module WinRPM

using Compat
using Compat.Sys: iswindows, isunix, BINDIR

if isunix()
    using HTTPClient.HTTPC
end

using Libz, LibExpat, URIParser

import Base: show, getindex, wait_close, pipeline_error

#export update, whatprovides, search, lookup, install, deps

if iswindows()
    const OS_ARCH = Sys.WORD_SIZE == 64 ? "mingw64" : "mingw32"
else
    const OS_ARCH = string(Sys.ARCH)
end

function mkdirs(dir)
    if !isdir(dir)
        mkdir(dir)
    end
end

const packages = ETree[]

function __init__()
    empty!(packages)
    global cachedir = joinpath(dirname(dirname(@__FILE__)), "cache")
    global installdir = joinpath(dirname(dirname(@__FILE__)), "deps")
    global indexpath = joinpath(cachedir, "index")

    mkdirs(cachedir)
    mkdirs(installdir)
    open(joinpath(dirname(@__FILE__), "..", "sources.list")) do f
        global sources = filter!(map(chomp, readlines(f))) do l
            return !isempty(l) && l[1] != '#'
        end
    end
    global installedlist = joinpath(dirname(@__FILE__), "..", "installed.list")
    update(false, false)
end

if isunix()
    function download(source::AbstractString)
        x = HTTPC.get(source)
        unsafe_string(x.body), x.http_code
    end
elseif iswindows()
    function download(source::AbstractString)
        ps = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
        tls12 = "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12"
        client = "New-Object System.Net.Webclient"
        # in the following we escape ' with '' (see https://ss64.com/ps/syntax-esc.html)
        filename = joinpath(tempdir(), split(source, "/")[end])        
        downloadfile = "($client).DownloadFile('$(replace(source, "'" => "''"))', '$(replace(filename, "'" => "''"))')"        
        run(`$ps -NoProfile -Command "$tls12; $downloadfile"`)                        
        readstring(filename), 200
    end
else
    error("Platform not supported: $(Sys.KERNEL)")
end

getcachedir(source) = getcachedir(cachedir, source)
function getcachedir(cachedir, source)
    open(indexpath, isfile(indexpath) ? "r+" : "w+") do cacheindex
        seek(cacheindex,0)
        lines = readlines(cacheindex)
        for (idx,line) in enumerate(lines)
            if !startswith(line,'#') && ' ' in line
                stri, src = split(chomp(line), ' ', limit=2)
                cache = joinpath(cachedir, stri)
                if !isdir(cache)
                    # remove this directory from the list,
                    # write out the new cacheindex file
                    # and restart
                    seek(cacheindex, 0)
                    truncate(cacheindex, 0)
                    for (idx2,l) in enumerate(lines)
                        if idx == idx2
                            write(cacheindex, '#')
                        end
                        write(cacheindex, l)
                    end
                    empty!(lines)
                    return getcachedir(source)
                end
                if source == src
                    return cache
                end
            end
        end
        # not found in existing cache
        i = 0
        local stri, cache
        while true
            i += 1
            stri = string(i)
            cache = joinpath(cachedir, stri)
            if !ispath(cache)
                try
                    mkdir(cache)
                    break
                end
            end
        end
        seekend(cacheindex)
        println(cacheindex, stri, ' ', source)
        flush(cacheindex)
        return cache
    end
end

function update(ignorecache::Bool=false, allow_remote::Bool=true)
    global sources, packages
    empty!(packages)
    for source in sources
        if source == "" || '\r' in source || '\n' in source
            continue
        end
        cache = getcachedir(source)
        function cacheget(path::AbstractString, never_cache::Bool)
            gunzip = false
            path2 = joinpath(cache,escape(path))
            if endswith(path2, ".gz")
                path2 = path2[1:end-3]
                gunzip = true
            end
            if !(ignorecache || (never_cache && allow_remote)) && isfile(path2)
                return read(path2, String)
            end
            if !allow_remote
                warn("skipping $path, not in cache -- call WinRPM.update() to download")
                return nothing
            end
            info("Downloading $source/$path")
            data = download("$source/$path")
            if data[2] != 200
                warn("received error $(data[2]) while downloading $source/$path")
                return nothing
            end
            body = gunzip ? Libz.decompress(convert(Vector{UInt8},data[1])) : data[1]
            open(path2, "w") do f
                write(f, body)
            end
            return String(body)
        end
        repomd = cacheget("repodata/repomd.xml", true)
        if repomd === nothing
           continue
        end
        xml = xp_parse(repomd)
        try
            for data = xml[xpath"/repomd/data[@type='primary']"]
                primary = cacheget(data[xpath"location/@href"][1], false)
                if primary === nothing
                    continue
                end
                pkgs = xp_parse(primary)[xpath"package[@type='rpm']"]
                pkgs["/"][1].attr["url"] = source
                for pkg in pkgs[xpath".[arch='noarch' or arch='src'][starts-with(name,'mingw32-') or starts-with(name, 'mingw64-')]"]
                    name = pkg[xpath"name"][1]
                    arch = pkg[xpath"arch"][1]
                    new_arch, new_name = split(LibExpat.string_value(name), '-', limit=2)
                    old_arch = LibExpat.string_value(arch)
                    if old_arch != "noarch"
                        new_arch = "$new_arch-$old_arch"
                    end
                    push!(empty!(name.elements), new_name)
                    push!(empty!(arch.elements), new_arch)
                end
                append!(packages,pkgs)
            end
        catch err
            warn("encounted invalid data while parsing repomd")
            rethrow(err)
            continue
        end
    end
end

struct Package
    pd::ETree
end
Package(p::Package) = p
Package(p::Vector{ETree}) = [Package(pkg) for pkg in p]

getindex(pkg::Package,x) = getindex(pkg.pd, x)

struct Packages{T<:Union{Set{ETree},Vector{ETree}}}
    p::T
end
Packages(pkgs::Vector{Package}) = Packages([p.pd for p in pkgs])
Packages(xpath::LibExpat.XPath) = Packages(packages[xpath])

getindex(pkg::Packages,x) = Package(getindex(pkg.p,x))
Base.length(pkg::Packages) = length(pkg.p)
Base.isempty(pkg::Packages) = isempty(pkg.p)
Base.start(pkg::Packages) = start(pkg.p)
Base.next(pkg::Packages,x) = ((p,s)=next(pkg.p,x); (Package(p),s))
Base.done(pkg::Packages,x) = done(pkg.p,x)

function show(io::IO, pkg::Package)
    println(io,"WinRPM Package: ")
    println(io,"  Name: ", names(pkg))
    println(io,"  Summary: ", LibExpat.string_value(pkg["summary"][1]))
    ver = pkg["version"][1]
    println(io,"  Version: ", ver.attr["ver"], " (rel ", ver.attr["rel"], ")")
    println(io,"  Arch: ", LibExpat.string_value(pkg["arch"][1]))
    println(io,"  URL: ", LibExpat.string_value(pkg["url"][1]))
    println(io,"  License: ", LibExpat.string_value(pkg["format/rpm:license"][1]))
    print(io,"  Description: ", replace(LibExpat.string_value(pkg["description"][1]), r"\r\n|\r|\n", "\n    "))
end

function show(io::IO, pkgs::Packages)
    print(io, "WinRPM Package Set:")
    if isempty(pkgs)
        print(io, "\n  <empty>")
    else
        for (i,pkg) = enumerate(pkgs)
            name = names(pkg)
            summary = LibExpat.string_value(pkg["summary"][1])
            arch = LibExpat.string_value(pkg["arch"][1])
            print(io,"\n  $i. $name ($arch) - $summary")
        end
    end
end

names(pkg::Package) = LibExpat.string_value(pkg["name"][1])
names(pkgs::Packages) = [names(pkg) for pkg in pkgs]

function select(pkgs::Packages, pkg::AbstractString)
    if length(pkgs) == 0
        error("Package candidate for $pkg not found")
    elseif length(pkgs) == 1
        pkg = pkgs[1]
    else
        info("Multiple package candidates found for $pkg, picking newest.")
        epochs = [getepoch(pkg) for pkg in pkgs]
        pkgs = pkgs[findin(epochs,maximum(epochs))]
        if length(pkgs) > 1
            versions = [convert(RPMVersionNumber, pkg[xpath"version/@ver"][1]) for pkg in pkgs]
            pkgs = pkgs[versions .== maximum(versions)]
            if length(pkgs) > 1
                release = [convert(VersionNumber, pkg[xpath"version/@rel"][1]) for pkg in pkgs]
                pkgs = pkgs[release .== maximum(release)]
                if length(pkgs) > 1
                    warn("Multiple package candidates have the same version, picking one at random")
                end
            end
        end
        pkg = pkgs[1]
    end
    pkg
end

lookup(name::AbstractString, arch::AbstractString=OS_ARCH) =
    Packages(xpath".[name='$name']['$arch'='' or arch='$arch']")

search(x::AbstractString, arch::AbstractString=OS_ARCH) =
    Packages(xpath".[contains(name,'$x') or contains(summary,'$x') or contains(description,'$x')]['$arch'='' or arch='$arch']")

whatprovides(file::AbstractString, arch::AbstractString=OS_ARCH) =
    Packages(xpath".[format/file[contains(text(),'$file')]]['$arch'='' or arch='$arch']")

rpm_provides(requires::AbstractString) =
    Packages(xpath".[format/rpm:provides/rpm:entry[@name='$requires']]")

function rpm_provides(requires::Union{Vector{T},Set{T}}) where T<:AbstractString
    pkgs = Set{ETree}()
    for x in requires
        pkgs_ = rpm_provides(x)
        if isempty(pkgs_)
            warn("Package not found that provides $x")
        else
            push!(pkgs, select(pkgs_,x).pd)
        end
    end
    Packages(pkgs)
end

rpm_requires(x::Package) = x[xpath"format/rpm:requires/rpm:entry/@name"]

function rpm_requires(xs::Union{Vector{Package},Set{Package},Packages})
    requires = Set{AbstractString}()
    for x in xs
        union!(requires, rpm_requires(x))
    end
    requires
end

function rpm_url(pkg::Package)
    baseurl = pkg[xpath"/@url"][1]
    arch = pkg[xpath"string(arch)"][1]
    href = pkg[xpath"location/@href"][1]
    url = baseurl, href
end

function rpm_ver(pkg::Union{Package,ETree})
    return (pkg[xpath"version/@ver"][1],
            pkg[xpath"version/@rel"][1],
            pkg[xpath"version/@epoch"][1])
end

struct RPMVersionNumber
    s::AbstractString
end
Base.convert(::Type{RPMVersionNumber}, s::AbstractString) = RPMVersionNumber(s)
Base.:(<)(a::RPMVersionNumber, b::RPMVersionNumber) = false
Base.:(==)(a::RPMVersionNumber, b::RPMVersionNumber) = true
Base.:(<=)(a::RPMVersionNumber, b::RPMVersionNumber) = (a == b) || (a < b)
Base.:(>)(a::RPMVersionNumber, b::RPMVersionNumber) = !(a <= b)
Base.:(>=)(a::RPMVersionNumber, b::RPMVersionNumber) = !(a < b)
Base.:(!=)(a::RPMVersionNumber, b::RPMVersionNumber) = !(a == b)

function getepoch(pkg::Package)
    epoch = pkg[xpath"version/@epoch"]
    if isempty(epoch)
        0
    else
        parse(Int, epoch[1])
    end
end

deps(pkg::AbstractString, arch::AbstractString=OS_ARCH) = deps(select(lookup(pkg, arch), pkg))
function deps(pkg::Union{Package,Packages})
    add = rpm_provides(rpm_requires(pkg))
    local packages::Vector{ETree}
    reqd = AbstractString[]
    if isa(pkg, Packages)
        packages = ETree[p for p in pkg.p]
    else
        packages = ETree[pkg.pd]
    end
    packages = union(packages, add.p)
    while !isempty(add)
        reqs = setdiff(rpm_requires(add), reqd)
        append!(reqd, reqs)
        add = Packages(setdiff(rpm_provides(reqs).p, packages))
        for p in add
            push!(packages, p.pd)
        end
    end
    return Packages(packages)
end

install(pkg::AbstractString, arch::AbstractString=OS_ARCH; yes=false) = install(select(lookup(pkg, arch), pkg); yes=yes)

function install(pkgs::Vector{T}, arch::AbstractString=OS_ARCH; yes=false) where T<:AbstractString
    todo = Package[]
    for pkg in pkgs
        push!(todo, select(lookup(pkg, arch), pkg))
    end
    install(Packages(todo); yes=yes)
end

function install(pkg::Union{Package,Packages}; yes=false)
    todo, toup = prepare_install(pkg)
    if isempty(todo) && isempty(toup)
        info("Nothing to do")
    else
        if !isempty(toup)
            info("Packages to update:  ", join(names(toup), ", "))
            yesold = yes || prompt_ok("Continue with updates")
        else
            yesold = false
        end
        if !isempty(todo)
            info("Packages to install: ", join(names(todo), ", "))
            yesnew = yes || prompt_ok("Continue with install")
        else
            yesnew = false
        end
        if yesold
            do_install(toup)
        end
        if yesnew
            do_install(todo)
        end
        info("Complete")
    end
end

function prepare_install(pkg::Union{Package,Packages})
    packages = deps(pkg).p
    open(installedlist, isfile(installedlist) ? "r+" : "w+") do installed
        seek(installed, 0)
        installed_list = Vector{AbstractString}[]
        for line in eachline(installed)
            ln = split(chomp(line), ' ', limit=2)
            if length(ln) == 2
                push!(installed_list, ln)
            end
        end
        toupdate = ETree[]
        filter!(packages) do p
            ver = replace(join(rpm_ver(p), ','), r"\s", "")
            oldver = false
            for entry in p[xpath"format/rpm:provides/rpm:entry[@name]"]
                provides = entry.attr["name"]
                maybe_oldver = false
                anyver = false
                for installed in installed_list
                    if installed[2] == provides
                        anyver = true
                        if ver == installed[1]
                            maybe_oldver = false
                            break
                        end
                        maybe_oldver = true
                    end
                end
                if !anyver
                    return true
                end
                oldver |= maybe_oldver
            end
            if oldver
                push!(toupdate, p)
            end
            return false
        end
        toup = Packages(reverse!(toupdate))
        todo = Packages(reverse!(packages))
        return todo, toup
    end
end

function do_install(packages::Packages)
    for package in packages
        do_install(package)
    end
end

const exe7z = iswindows() ? joinpath(BINDIR, "7z.exe") : "7z"

function do_install(package::Package)
    name = names(package)
    source, path = rpm_url(package)
    info("Downloading: ", name)
    data = download("$source/$path")
    if data[2] != 200
        info("try running WinRPM.update() and retrying the install")
        error("failed to download $name $(data[2]) from $source/$path.")
    end
    cache = getcachedir(source)
    path2 = joinpath(cache,escape(path))
    open(path2, "w") do f
        write(f, data[1])
    end
    info("Extracting: ", name)
    cpio = splitext(path2)[1]*".cpio"
    local err = nothing
    for cmd = [`$exe7z x -y $path2 -o$cache`, `$exe7z x -y $cpio -o$installdir`]
        (out, pc) = open(cmd, "r")
        stdoutstr = read(out, String)
        if !success(pc)
            wait_close(out)
            println(stdoutstr)
            err = pc
            if isunix()
                cd(installdir) do
                    if success(`rpm2cpio $path2` | `cpio -imud`)
                        err = nothing
                    end
                end
            end
            isfile(cpio) && rm(cpio)
            err !== nothing && pipeline_error(err)
            break
        end
    end
    isfile(cpio) && rm(cpio)
    ver = replace(join(rpm_ver(package), ','), r"\s", "")
    open(installedlist, isfile(installedlist) ? "r+" : "w+") do installed
        for entry in package[xpath"format/rpm:provides/rpm:entry[@name]"]
            provides = entry.attr["name"]
            seekend(installed)
            println(installed, ver, ' ', provides)
        end
        flush(installed)
    end
end

function prompt_ok(question)
    while true
        print(question)
        print(" [y/N]? ")
        ans = strip(readline(STDIN))
        if isempty(ans) || ans[1] == 'n' || ans[1] == 'N'
            return false
        elseif ans[1] == 'y' || ans[1] == 'Y'
            return true
        end
        println("Please answer Y or N")
    end
end

include("winrpm_bindeps.jl")

# deprecations 
@deprecate help() "Please see the README.md file at https://github.com/JuliaPackaging/WinRPM.jl"

end
