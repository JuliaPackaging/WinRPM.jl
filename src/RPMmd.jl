module RPMmd

using URLParse
using HTTP.Util
require("HTTP/src/Client")
using HTTPClient
using Zlib
using LibExpat

import Base: show, getindex


const cachedir = Pkg.dir("RPMmd", "cache")
const packages = ParsedData[]

function mkdirs(dir)
    if !isdir(dir)
        mkdir(dir)
    end
end

function init()
    mkdirs(cachedir)
    open(Pkg.dir("RPMmd", "sources.list")) do f
        global const sources = readlines(f,chomp)
    end
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
            for data = xml["repomd"]["data"]
                if data.name == "data" && get(data.attr,"type","") == "primary"
                    primary = cacheget("$_url/$(data["location"][1].attr["href"])", false)
                    if primary === nothing
                        continue
                    end
                    push!(packages,xp_parse(primary))
                end
            end
        catch err
            warn("encounted invalid data while parsing repomd")
            println(err)
            continue
        end
        if hasconn
            HTTPClient.close(conn)
        end
    end
end


init()

end
