using WinRPM
using Base.Test

Pkg.add("HDF5")
Pkg.build("HDF5")
Pkg.test("HDF5")
