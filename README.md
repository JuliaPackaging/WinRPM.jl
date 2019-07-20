Introduction
============

WinRPM is an installer for RPM packages provided by an RPM-md build system.
The default RPM-md provider is the [OpenSUSE build service](https://build.opensuse.org/),
which builds 32- and 64-bit DLLs for libraries used by
several Julia packages (note: builds are cross-compiled).

Installation
------------

To install WinRPM via the Julia package manager, use:

```julia
Pkg.add("WinRPM")
```

Package Availability
--------------------

To search for a package from within Julia:

```julia
using WinRPM

WinRPM.search("packagename")
```

See also: upstream package information for [Win64](https://build.opensuse.org/project/show/windows%3Amingw%3Awin64)
and [Win32](https://build.opensuse.org/project/show/windows%3Amingw%3Awin32)

Package Installation
--------------------

To install a library using WinRPM:

```julia
WinRPM.install("gtk2")
WinRPM.install("win_iconv","mingw32")
```

Dependencies
------------

WinRPM will automatically install dependencies declared in the RPM-md package specification.

Package Creation
----------------

Please see the OpenSUSE build service [packaging guidelines](http://en.opensuse.org/openSUSE:Packaging_guidelines)
for further information.

BinDeps Integration
===================

WinRPM may be integrated with the [BinDeps](https://github.com/JuliaLang/BinDeps.jl)
system by declaring a `provides(WinRPM.RPM...` line for each serviceable dependency.

For example, in the [Tk.jl](https://github.com/JuliaLang/Tk.jl)
package the following lines declare availability of the `tcl` and `tk` libraries
from WinRPM:

```julia
if Sys.iswindows()
    using WinRPM
    provides(WinRPM.RPM, "tk", tk, os=:Windows)
    provides(WinRPM.RPM, "tcl", tcl, os=:Windows)
end
```

These lines must be preceded by `BinDeps.library_dependency` declarations;
please see the BinDeps documentation for more information.

It may also be helpful to review usage examples in Tk.jl or other existing packages
(see `deps/build.jl`): [Nettle.jl](https://github.com/staticfloat/Nettle.jl)
[Cairo.jl](https://github.com/JuliaLang/Cairo.jl)


Stand-alone Usage
=================

For stand-alone use, add the following lines to your `%APPDATA%/julia/.juliarc.jl` file:

```julia
RPMbindir = Pkg.dir("WinRPM","deps","usr","$(Sys.ARCH)-w64-mingw32","sys-root","mingw","bin")
push!(Libdl.DL_LOAD_PATH,RPMbindir)
ENV["PATH"]=ENV["PATH"]*";"*RPMbindir
```

Full API
========

RPM-md provides the following functions for general usage:
`update`, `whatprovides`, `search`, `lookup`, and `install`

`update()` -- download the new metadata from the hosts. Additional hosts can be added by editing the file `sources.list`.

`whatprovides(file)` -- given a part of a filename or file-path, returns a list of packages that include

`search(string)` -- search for a string in the package description, summary, or name fields and returns a list of matching packages

`lookup(name)` -- search for a package by name

`install(pkg)` -- install a package (by name or package identifier), including dependencies, into the `deps` folder

The functions typically take a second parameter "arch" specifying the package architecture for search, defaulting to the current operating system.
It also offers the keyword argument `yes` which should be set to `true` if no prompt is desired.

Usage Example
=============

Package lists can be further filtered and analyzed, as the following example demonstrates:

```julia
julia> using WinRPM

julia> gtk3_candidates = WinRPM.search("gtk3", "mingw32")
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

julia> WinRPM.install(gtk3_pkg)
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
julia> WinRPM.install("gtk3")
```
