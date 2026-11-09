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

-- Dependency versions are provided by versions/build.ver.
local function required_version(name)
    local value = os.getenv(name)
    if not value or value == "" then
        LmodError("Missing " .. name ..
                  "; source versions/build.ver before loading ursa_wrf")
    end
    return value
end

-- Compiler and MPI
load("intel-oneapi-compilers/" .. required_version("intel_compiler_ver"))
load("intel-oneapi-mpi/" .. required_version("intel_mpi_ver"))

-- I/O dependencies
load("netcdf-c/" .. required_version("netcdf_c_ver"))
load("netcdf-fortran/" .. required_version("netcdf_fortran_ver"))
load("hdf5/" .. required_version("hdf5_ver"))
load("parallel-netcdf/" .. required_version("parallel_netcdf_ver"))
load("libtirpc/" .. required_version("libtirpc_ver"))

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


