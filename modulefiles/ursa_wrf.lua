-- ursa_wrf.lua
-- NOAA Ursa environment for building and running WoFS WRF
-- Intel OneAPI / Intel MPI / NetCDF / HDF5 / PnetCDF / libtirpc

help([[
WoFS WRF environment on NOAA Ursa.

Provides the validated compiler, MPI, and library dependencies
for building WRF with hybrid vertical coordinates.
]])

whatis("Name: ursa_wrf")
whatis("Description: WoFS WRF build/runtime environment on Ursa")

-- Compiler and MPI
load("intel-oneapi-compilers/2023.2.0")
load("intel-oneapi-mpi/2021.13.1")

-- I/O dependencies
load("netcdf-c/4.9.2")
load("netcdf-fortran/4.6.1")
load("hdf5/1.14.3")
load("parallel-netcdf/1.12.3")
load("libtirpc/1.3.3")

-- WRF build configuration
setenv("WRF_EM_CORE", "1")
setenv("WRFIO_NCD_LARGE_FILE_SUPPORT", "1")
setenv("NETCDF_classic", "0")

-- Resolve NetCDF installation roots using loaded modules
local nc = capture("nc-config --prefix 2>/dev/null"):gsub("%s+$", "")
local nf = capture("nf-config --prefix 2>/dev/null"):gsub("%s+$", "")
local pn = capture("pnetcdf-config --prefix 2>/dev/null"):gsub("%s+$", "")

if nc ~= "" then
    setenv("NETCDF_C", nc)
end

if nf ~= "" then
    setenv("NETCDF_FORTRAN", nf)
end

if pn ~= "" then
    setenv("PNETCDF", pn)
end

-- libtirpc installation root is provided by its module.
-- The build script should verify LIBTIRPC_ROOT.


