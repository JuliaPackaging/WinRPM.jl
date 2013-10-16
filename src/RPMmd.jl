module RPMmd

@unix_only using HTTPClient.HTTPC
using Zlib
using LibExpat
using URLParse

import Base: show, getindex

#export update, whatprovides, search, lookup, install, deps, help

const cachedir = Pkg.dir("RPMmd", "cache")
const installdir = Pkg.dir("RPMmd", "deps")
const packages = ParsedData[]

if OS_NAME == :Windows
    const OS_ARCH = WORD_SIZE == 64 ? "mingw64" : "mingw32"
else
    const OS_ARCH = string(Sys.ARCH)
end

function mkdirs(dir)
    if !isdir(dir)
        mkdir(dir)
    end
end

function init()
    mkdirs(cachedir)
    mkdirs(installdir)
    open(Pkg.dir("RPMmd", "sources.list")) do f
        global const sources = filter!(readlines(f,chomp)) do l
            return !isempty(l) && l[1] != '#'
        end
    end
    installedlist = Pkg.dir("RPMmd", "installed.list")
    if !isfile(installedlist)
        global const installed = open(installedlist, "w+")
    else
        global const installed = open(installedlist, "r+")
    end
    update(false, false)
end

@unix_only download(source::ByteString) = (x=HTTPC.get(source); (x.body,x.http_status))
@windows_only function download(source::ByteString)
    #res = ccall((:URLDownloadToFileA,:urlmon),stdcall,Cuint,
    #    (Ptr{Void},Ptr{Uint8},Ptr{Uint8},Cint,Ptr{Void}),
    #    0,source,dest,0,0)
    dest = Array(Uint8,1000)
    res = ccall((:URLDownloadToCacheFileA,:urlmon),stdcall,Cuint,
        (Ptr{Void},Ptr{Uint8},Ptr{Uint8},Clong,Cint,Ptr{Void}),
        0,source,dest,length(dest),0,0)
    if res == 0
        filename = bytestring(pointer(dest))
        if isfile(filename)
            return readall(filename),200
        else
            return "",0
        end
    else
        return "",0
    end
end

function update(ignorecache::Bool=false, allow_remote::Bool=true)
    global sources, packages
    empty!(packages)
    for source in sources
        if source == ""
            continue
        end
        cache = joinpath(cachedir, escape(source))
        mkdirs(cache)
        function cacheget(path::ASCIIString, never_cache::Bool)
            gunzip = false
            path2 = joinpath(cache,escape(path))
            if endswith(path2, ".gz")
                path2 = path2[1:end-3]
                gunzip = true
            end
            if !(ignorecache || (never_cache && allow_remote)) && isfile(path2)
                return readall(path2)
            end
            if !allow_remote
                warn("skipping $path, not in cache")
                return nothing
            end
            info("Downloading $source/$path")
            data = download("$source/$path")
            if data[2] != 200
                warn("received error $(data[2]) while downloading $source/$path")
                return nothing
            end
            body = gunzip ? decompress(data[1]) : data[1]
            open(path2, "w") do f
                write(f, body)
            end
            return bytestring(body)
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
                    new_arch, new_name = split(LibExpat.string_value(name), '-', 2)
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

immutable Package
    pd::ParsedData
end
Package(p::Package) = p
Package(p::Vector{ParsedData}) = [Package(pkg) for pkg in p]

getindex(pkg::Package,x) = getindex(pkg.pd,x)

immutable Packages{T<:Union(Set{ParsedData},Vector{ParsedData},)}
    p::T
end
Packages{T<:Union(Set{ParsedData},Vector{ParsedData})}(pkgs::T) = Packages{T}(pkgs)
Packages(pkgs::Vector{Package}) = Packages([p.pd for p in pkgs])
function Packages(xpath::String, arch::String="")
    if arch != ""
        xpath = xpath*"[arch='$arch']"
    end
    Packages(packages[xpath])
end
getindex(pkg::Packages,x) = Package(getindex(pkg.p,x))
Base.length(pkg::Packages) = length(pkg.p)
Base.isempty(pkg::Packages) = isempty(pkg.p)
Base.start(pkg::Packages) = start(pkg.p)
Base.next(pkg::Packages,x) = ((p,s)=next(pkg.p,x); (Package(p),s))
Base.done(pkg::Packages,x) = done(pkg.p,x)

function show(io::IO, pkg::Package)
    println(io,"Name: ", names(pkg))
    println(io,"Summary: ", LibExpat.string_value(pkg["summary"][1]))
    ver = pkg["version"][1]
    println(io,"Version: ", ver.attr["ver"], " (rel ", ver.attr["rel"], ")")
    println(io,"Arch: ", LibExpat.string_value(pkg["arch"][1]))
    println(io,"URL: ", LibExpat.string_value(pkg["url"][1]))
    println(io,"License: ", LibExpat.string_value(pkg["format/rpm:license"][1]))
    println(io,"Description: ", LibExpat.string_value(pkg["description"][1]))
end

function show(io::IO, pkgs::Packages)
    for (i,pkg) = enumerate(pkgs)
        name = names(pkg)
        summary = LibExpat.string_value(pkg["summary"][1])
        arch = LibExpat.string_value(pkg["arch"][1])
        println(io,"$i. $name ($arch) - $summary")
    end
end

names(pkg::Package) = LibExpat.string_value(pkg["name"][1])
names(pkgs::Packages) = [names(pkg) for pkg in pkgs]

function lookup(name::String, arch::String=OS_ARCH)    
    Packages(".[name='$name']", arch)
end

search(x::String, arch::String=OS_ARCH) =
    Packages(".[in(name,'$x') or in(summary,'$x') or in(description,'$x')]", arch)

whatprovides(file::String, arch::String=OS_ARCH) =
    Packages(".[format/file[in(text(),'$file')]]", arch)

rpm_provides(requires::String) =
    Packages(".[format/rpm:provides/rpm:entry[@name='$requires']]")

function rpm_provides{T<:String}(requires::Union(Vector{T},Set{T}))
    pkgs = Set{ParsedData}()
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

function rpm_requires(xs::Union(Vector{Package},Set{Package},Packages))
    requires = Set{String}()
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

type RPMVersionNumber
    s::String
end
Base.convert(::Type{RPMVersionNumber}, s::String) = RPMVersionNumber(s)
Base.(:(<))(a::RPMVersionNumber,b::RPMVersionNumber) = false
Base.(:(==))(a::RPMVersionNumber,b::RPMVersionNumber) = true
Base.(:(<=))(a::RPMVersionNumber,b::RPMVersionNumber) = (a==b)||(a<b)
Base.(:(>))(a::RPMVersionNumber,b::RPMVersionNumber) = !(a<=b)
Base.(:(>=))(a::RPMVersionNumber,b::RPMVersionNumber) = !(a<b)
Base.(:(!=))(a::RPMVersionNumber,b::RPMVersionNumber) = !(a==b)

function getepoch(pkg::Package)
    epoch = pkg[xpath"version/@epoch"]
    if isempty(epoch)
        0
    else
        int(epoch)
    end
end
function select(pkgs::Packages, pkg::String)
    if length(pkgs) == 0
        error("Package candidate for $pkg not found")
    elseif length(pkgs) == 1
        pkg = pkgs[1]
    else
        info("Multiple package candidates found for $pkg, picking newest.")
        epochs = [getepoch(pkg) for pkg in pkgs]
        pkgs = pkgs[findin(epochs,max(epochs))]
        if length(pkgs) > 1
            versions = [convert(RPMVersionNumber, pkg[xpath"version/@ver"][1]) for pkg in pkgs]
            pkgs = pkgs[versions .== max(versions)]
            if length(pkgs) > 1
                release = [convert(VersionNumber, pkg[xpath"version/@rel"][1]) for pkg in pkgs]
                pkgs = pkgs[release .== max(release)]
                if length(pkgs) > 1
                    warn("Multiple package candidates have the same version, picking one at random")
                end
            end
        end
        pkg = pkgs[1]
    end
    pkg
end

deps(pkg::String, arch::String=OS_ARCH) = deps(select(lookup(pkg, arch), pkg))
function deps(pkg::Union(Package,Packages))
    add = rpm_provides(rpm_requires(pkg))
    packages::Vector{ParsedData}
    reqd = String[]
    seek(installed,0)
    if isa(pkg,Packages)
        packages = [p for p in pkg.p]
    else
        packages = ParsedData[pkg.pd,]
    end
    packages = union(packages, add.p)
    while !isempty(add)
        reqs = setdiff(rpm_requires(add), reqd)
        append!(reqd,reqs)
        add = Packages(setdiff(rpm_provides(reqs).p,packages))
        for p in add
            push!(packages, p.pd)
        end
    end
    return Packages(packages)
end

install(pkg::String, arch::String=OS_ARCH; yes = false) = install(select(lookup(pkg, arch),pkg); yes = yes)

function install(pkgs::Vector{ASCIIString}, arch = OS_ARCH; yes = false)
    todo = Package[]
    for pkg in pkgs
        push!(todo,select(lookup(pkg, arch),pkg))
    end
    install(Packages(todo); yes = yes)
end

function install(pkg::Union(Package,Packages); yes = false)
    packages = deps(pkg).p
    installed_list = readlines(installed,chomp)
    filter!(packages) do p
        for entry in p[xpath"format/rpm:provides/rpm:entry[@name]"]
            provides = entry.attr["name"]
            if !in(installed_list, provides)
                return true
            end
        end
        return false
    end
    if isempty(packages)
        info("Nothing to do")
    else
        todo = Packages(reverse!(packages))
        info("Packages to install: ", join(names(todo), ", "))
        if yes || prompt_ok("Continue with install")
            do_install(todo)
            info("Success")
        end
    end
end

function do_install(packages::Packages)
    for package in packages
        do_install(package)
    end
end

function do_install(package::Package)
    name = names(package)
    source,path = rpm_url(package)
    info("Downloading: ", name)
    data = download("$source/$path")
    if data[2] != 200
        info("try running RPMmd.update() and retrying the install")
        error("failed to download $name $(data[2]) from $source/$path.")
    end
    cache = joinpath(cachedir,escape(source))
    path2 = joinpath(cache,escape(path))
    open(path2, "w") do f
        write(f, data[1])
    end
    info("Extracting: ", name)
    cpio = splitext(path2)[1]*".cpio"
    local err = nothing
    try
        run(`7z x -y $path2 -o$cache`)
        run(`7z x -y $cpio -o$installdir`)
    catch e
        err = e
        @unix_only cd(installdir) do
            if success(`rpm2cpio $path2` | `cpio -imud`)
                err = nothing
            end
        end
    end
    if isfile(cpio)
        rm(cpio)
    end
    if err !== nothing
        rethrow(e)
    end
    for entry in package[xpath"format/rpm:provides/rpm:entry[@name]"]
        provides = entry.attr["name"]
        println(installed, provides)
    end
    flush(installed)
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

function help()
    less(Pkg.dir("RPMmd","README.md"))
end

include("bindeps.jl")

init()

end

