help([[
WoFS v1.0 IC_PREP runtime environment on NOAA Ursa.
Provides UPP runtime libraries and IC_PREP utilities.
]])

whatis("Description: WoFS v1.0 IC_PREP runtime environment")

local spack = "/apps/spack-2024-12/linux-rocky9-x86_64/gcc-11.4.1"

-- UPP runtime libraries verified on Ursa
local jasper = spack .. "/jasper-2.0.32-ti3pzbhcmtzczjmisaaqn724zvjdm4td/lib64"

local mkl_root = spack .. "/intel-oneapi-mkl-2024.2.1-jdwsjbesf33xtjx7unabao2hg4x5lovm"

local mkl = mkl_root .. "/mkl/2024.2/lib"
local intel = mkl_root .. "/compiler/2024.2/lib"

local netcdff = spack .. "/netcdf-fortran-4.6.1-rxwle72kj3anm4uess3ixiqg7ezgq4vk/lib"

prepend_path("LD_LIBRARY_PATH", jasper)
prepend_path("LD_LIBRARY_PATH", mkl)
prepend_path("LD_LIBRARY_PATH", intel)
prepend_path("LD_LIBRARY_PATH", netcdff)

-- NetCDF runtime dependencies
load("netcdf-c/4.9.2")

-- Python runtime for IC_PREP
-- Provides PyYAML, NumPy, netCDF4, and SciPy on Ursa.
load("intel-oneapi-mpi/2021.13.1")
local python_ver = os.getenv("python_ver")

if not python_ver or python_ver == "" then
    LmodError("python_ver must be defined in versions/run.ver")
end

load("python/" .. python_ver)

-- IC_PREP utilities
load("ncl/6.6.2")
load("nco/5.2.4")
load("wgrib2/3.1.3_wmo")
