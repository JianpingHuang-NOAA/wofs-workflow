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

-- Legacy WPS compiler and MPI runtime
-- Matches the verified Ursa WPS executables.
load("intel-oneapi-compilers/2023.2.0")
load("intel-oneapi-mpi/2021.13.1")

-- NetCDF runtime
load("netcdf-c/4.9.2")
load("netcdf-fortran/4.6.1")
load("parallel-netcdf/1.12.3")

-- Python runtime for YAML configuration and processing
local python_ver = os.getenv("python_ver")

if python_ver == nil or python_ver == "" then
    LmodError("python_ver is not defined. Source versions/run.ver first.")
end

load("python/" .. python_ver)

-- BC_PREP processing utilities
load("ncl/6.6.2")
load("nco/5.2.4")
load("wgrib2/3.1.3_wmo")

-- Runtime libraries used by the existing Ursa environment
local spack = "/apps/spack-2024-12/linux-rocky9-x86_64/gcc-11.4.1"

local jasper =
    spack .. "/jasper-2.0.32-ti3pzbhcmtzczjmisaaqn724zvjdm4td/lib64"


prepend_path("LD_LIBRARY_PATH", jasper)
