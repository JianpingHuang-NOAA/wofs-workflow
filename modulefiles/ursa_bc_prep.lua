help([[
WoFS v1.0 BC_PREP runtime environment on NOAA Ursa.

Supports boundary-condition preprocessing:
  UNGRIB
  METGRID
  REAL
  MEAN
  PERTURB
]])

whatis("Description: WoFS v1.0 BC_PREP runtime environment")

-- Dependency versions are provided by versions/run.ver.
local function required_version(name)
    local value = os.getenv(name)

    if not value or value == "" then
        LmodError("Missing " .. name ..
                  "; source versions/run.ver first")
    end

    return value
end


-- Legacy WPS compiler and MPI runtime
-- Matches the verified Ursa WPS executables.
load("intel-oneapi-compilers/" .. required_version("intel_compiler_ver"))
load("intel-oneapi-mpi/" .. required_version("intel_mpi_ver"))

-- NetCDF runtime
load("netcdf-c/" .. required_version("netcdf_c_ver"))
load("netcdf-fortran/" .. required_version("netcdf_fortran_ver"))
load("parallel-netcdf/" .. required_version("parallel_netcdf_ver"))

-- Python runtime for YAML configuration and processing
load("python/" .. required_version("python_ver"))

-- BC_PREP processing utilities
load("ncl/" .. required_version("ncl_ver"))
load("nco/" .. required_version("nco_ver"))
load("wgrib2/" .. required_version("wgrib2_ver"))

-- Runtime libraries used by the existing Ursa environment
local spack = "/apps/spack-2024-12/linux-rocky9-x86_64/gcc-11.4.1"

local jasper =
    spack .. "/jasper-2.0.32-ti3pzbhcmtzczjmisaaqn724zvjdm4td/lib64"


prepend_path("LD_LIBRARY_PATH", jasper)
