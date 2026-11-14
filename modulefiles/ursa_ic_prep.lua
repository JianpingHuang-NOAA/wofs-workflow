help([[
WoFS v1.0 IC_PREP runtime environment on NOAA Ursa.
Provides UPP runtime libraries and IC_PREP utilities.
]])

whatis("Description: WoFS v1.0 IC_PREP runtime environment")

-- Dependency versions are provided by versions/run.ver.
local function required_version(name)
    local value = os.getenv(name)

    if not value or value == "" then
        LmodError("Missing " .. name ..
                  "; source versions/run.ver first")
    end

    return value
end


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
load("netcdf-c/" .. required_version("netcdf_c_ver"))

-- Python runtime for IC_PREP
-- Provides PyYAML, NumPy, netCDF4, and SciPy on Ursa.
load("intel-oneapi-mpi/" .. required_version("intel_mpi_ver"))
load("python/" .. required_version("python_ver"))

-- IC_PREP utilities
load("ncl/" .. required_version("ncl_ver"))
load("nco/" .. required_version("nco_ver"))
load("wgrib2/" .. required_version("wgrib2_ver"))
