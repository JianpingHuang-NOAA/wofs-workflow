help([[
WoFS v1.0 UPP build environment on NOAA Ursa.

Extends the isolated UPP runtime environment with
CMake and Intel MPI compiler wrappers.
]])

whatis("Description: WoFS UPP build environment")

local cmake_ver = os.getenv("cmake_ver")

if not cmake_ver or cmake_ver == "" then
    LmodError("cmake_ver must be defined in versions/build.ver")
end

-- Reuse the centralized UPP environment.
load("ursa_upp")

-- Build-specific dependency.
load(pathJoin("cmake", cmake_ver))

-- Intel MPI compiler wrappers.
setenv("CC", "mpiicx")
setenv("CXX", "mpiicpx")
setenv("FC", "mpiifort")

setenv("I_MPI_CC", "icx")
setenv("I_MPI_CXX", "icpx")
setenv("I_MPI_FC", "ifort")
setenv("I_MPI_F77", "ifort")
setenv("I_MPI_F90", "ifort")
