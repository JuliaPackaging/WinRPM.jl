This is a front-end installer for RPM-md packages.

To use, add the following lines to your `%APPDATA%/julia/.juliarc.jl` file:

```julia
RPMbindir = Pkg.dir("RPMmd","deps","usr","$(Sys.ARCH)-w64-mingw32","sys-root","mingw","bin")
push!(DL_LOAD_PATH,RPMbindir)
ENV["PATH"]=ENV["PATH"]*";"*RPMbindir
```

And add the package manager to your julia environment:

```julia
Pkg.add("RPMmd")
require("RPMmd")
RPMmd.update()
```

Now you can search and install binaries:

```julia
require("RPMmd")
RPMmd.install("gtk2")
RPMmd.install("win_iconv","mingw32")
```

---

RPM-md provides the following functions for general usage:
`update`, `whatprovides`, `search`, `lookup`, and `install`

`update()` -- download the new metadata from the hosts. Additional hosts can be added by editing the file `sources.list`.

`whatprovides(file)` -- given a part of a filename or file-path, returns a list of packages that include

`search(string)` -- search for a string in the package description, summary, or name fields and returns a list of matching packages

`lookup(name)` -- search for a package by name

`install(pkg)` -- install a package (by name or package identifier), including dependencies, into the `deps` folder

The functions typically take a second parameter "arch" specifying the package architecture for search, defaulting to the current operating system.

Package lists can be further filtered and analyzed, as the following example demonstrates:

```julia
julia> using RPMmd

julia> gtk3_candidates = RPMmd.search("gtk3", "mingw32")
1. webkitgtk3-debug (mingw32) - Debug information for package mingw32-webkitgtk3
2. webkitgtk3-lang (mingw32) - Languages for package mingw32-webkitgtk3
3. webkitgtk3-tools (mingw32) - Library for rendering web content, GTK+ 3 Port (tools)
4. gtk3-data (mingw32) - The GTK+ toolkit library (version 3) -- Data Files
5. gtk3-lang (mingw32) - Languages for package mingw32-gtk3
6. gtk3 (mingw32) - The GTK+ toolkit library (version 3)
7. gtk3-devel (mingw32) - The GTK+ toolkit library (version 3) -- Development Files
8. gtk3-debug (mingw32) - Debug information for package mingw32-gtk3
9. gtk3-tools (mingw32) - The GTK+ toolkit library (version 3) -- Tools
10. libwebkitgtk3 (mingw32) - Library for rendering web content, GTK+ 3 Port
11. libwebkitgtk3-devel (mingw32) - Library for rendering web content, GTK+ 3 Port (development files)

julia> gtk3_pkg = gtk3_candidates[6]
Name: gtk3
Summary: The GTK+ toolkit library (version 3)
Version: 3.8.1 (rel 1.31)
Arch: mingw32
URL: http://www.gtk.org/
License: LGPL-2.0+
Description: GTK+ is a multi-platform toolkit for creating graphical user interfaces.
Offering a complete set of widgets, GTK+ is suitable for projects
ranging from small one-off projects to complete application suites.

julia> RPMmd.install(gtk3_pkg)
MESSAGE: Installing: libxml2, atk, gdk-pixbuf, liblzma, zlib, libpng, libtiff, pixman, freetype, libffi, glib2-lang, atk-lang, libjpeg, gdk-pixbuf-lang, libharfbuzz, glib2, fontconfig, libcairo2, libjasper, libgcc, libintl, gtk3
MESSAGE: Downloading: libxml2
MESSAGE: Extracting: libxml2
2286 blocks
MESSAGE: Downloading: atk
MESSAGE: Extracting: atk
263 blocks
...
MESSAGE: Downloading: gtk3
MESSAGE: Extracting: gtk3
9614 blocks
MESSAGE: Success

julia> # or we can just install it directly
julia> RPMmd.install("gtk3")
```
