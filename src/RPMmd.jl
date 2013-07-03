module RPMmd

using URLParse
require("HTTP/src/Client")
using HTTPClient
using Zlib
using LibExpat

import Base: show, getindex

export update, whatprovides, search, lookup, install, deps

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
        global const sources = readlines(f,chomp)
    end
    global const installed = open(Pkg.dir("RPMmd", "installed.list"), "r+")
    update(false, false)
end

function urlinfo(source)
    url = urlsplit(source, "http", false)
    if username(url) !== nothing ||
        password(url) !== nothing ||
        url.scheme != "http" ||
        url.params != "" ||
        url.fragment != "" ||
         hostname(url) === nothing
         warn("skipping unsupported url \"$source\"")
         return ("",0,"")
    end
    _hostname::ASCIIString = hostname(url)
    _port::Int = ((p = port(url)) == nothing ? 80 : p)
    _url::ASCIIString = url.url
    if _url[end] == '/'
        _url = _url[1:end-1]
    end
    return (_hostname, _port, _url)
end

function get(source::String)
    hostname, port, url = urlinfo(source)
    if port == 0 || hostname == ""
        return nothing
    end
    get(hostname, port, url)
end

get(hostname::String, port::Int, path::String) = get(HTTPClient.open(hostname, port), path)

function get(conn::HTTPClient.Connection, path::String)
    data = HTTPClient.get(conn, path)
    while data.status == 301 || data.status == 302 || data.status == 303
        loc2 = data.headers["Location"][1]
        _hostname2, _port2, _url2 = urlinfo(loc2)
        if _port2 == 0 || _hostname2 == ""
            break
        end
        conn2 = HTTPClient.open(_hostname2, _port2)
        data = HTTPClient.get(conn2, _url2)
        HTTPClient.close(conn2)
    end
    data
end

function update(ignorecache::Bool=false, allow_remote::Bool=true)
    global sources, packages
    empty!(packages)
    for source in sources
        if source == ""
            continue
        end
        _hostname, _port, _url = urlinfo(source)
        if _port == 0 || _hostname == ""
            continue
        end
        cache = joinpath(cachedir, escape(_hostname))
        mkdirs(cache)
        local conn::HTTPClient.Connection, hasconn::Bool=false
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
            if !hasconn
                info("Connecting to $_hostname")
                conn = HTTPClient.open(_hostname, _port)
                hasconn = true
            end
            info("Downloading $path")
            data = get(conn, path)
            if data.status != 200
                warn("received error $(data.status) $(data.phrase) while downloading $path")
                return nothing
            end
            body = gunzip ? decompress(data.body) : data.body
            open(path2, "w") do f
                write(f, body)
            end
            return bytestring(body)
        end
        repomd = cacheget("$_url/repodata/repomd.xml", true)
        if repomd === nothing
           continue
        end
        xml = xp_parse(repomd)
        try
            for data = xml["/repomd/data[@type='primary']"]
                primary = cacheget("$_url/$(data["location"][1].attr["href"])", false)
                if primary === nothing
                    continue
                end
                pkgs = xp_parse(primary)["package[@type='rpm']"]
                pkgs["/"][1].attr["url"] = source
                for pkg in pkgs[".[arch='noarch' or arch='src'][starts-with(name,'mingw32-') or starts-with(name, 'mingw64-')]"]
                    name = pkg["name"][1]
                    arch = pkg["arch"][1]
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
        if hasconn
            HTTPClient.close(conn)
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
    Packages(".[contains(name,'$x') or contains(summary,'$x') or contains(description,'$x')]", arch)

whatprovides(file::String, arch::String=OS_ARCH) =
    Packages(".[format/file[contains(text(),'$file')]]", arch)

rpm_provides(requires::String) =
    Packages(".[format/rpm:provides/rpm:entry[@name='$requires']]")

function rpm_provides{T<:String}(requires::Union(Vector{T},Set{T}))
    pkgs = Set{ParsedData}()
    for x in requires
        pkgs_ = rpm_provides(x)
        if isempty(pkgs_)
            warn("Package not found that provides $x")
        else
            add!(pkgs, select(pkgs_,x).pd)
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
    url = "$baseurl/$href"
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

install(pkg::String, arch::String=OS_ARCH) = install(select(lookup(pkg, arch),pkg))

function install(pkg::Union(Package,Packages))
    packages = deps(pkg).p
    installed_list = readlines(installed,chomp)
    filter!(packages) do p
        for entry in p[xpath"format/rpm:provides/rpm:entry[@name]"]
            provides = entry.attr["name"]
            if !contains(installed_list, provides)
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
        if prompt_ok("Continue with install")
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
    url = rpm_url(package)
    hostname, port, path = urlinfo(url)
    if port == 0 || hostname == ""
        error("could not parse url $url for $name")
    end
    info("Downloading: ", name)
    data = get(hostname, port, path)
    if data.status != 200
        info("try running RPMmd.update() and retrying the install")
        error("failed to download $name $(data.status) $(data.phrase) from $url.")
    end
    cache = joinpath(cachedir,escape(hostname))
    path2 = joinpath(cache,escape(path))
    open(path2, "w") do f
        write(f, data.body)
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
        reraise(e)
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

init()

end

