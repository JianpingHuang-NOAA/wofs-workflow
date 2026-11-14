help([[
WoFS v1.0 isolated UPP runtime environment on NOAA Ursa.
Provides Intel-compatible MPI and UPP runtime libraries.
]])

whatis("Description: WoFS isolated UPP runtime environment")

local function required_version(name)
    local value = os.getenv(name)

    if not value or value == "" then
        LmodError(name .. " must be defined in versions/run.ver")
    end

    return value
end

local spack_ver = required_version("spack_stack_ver")
local oneapi_ver = required_version("stack_oneapi_ver")
local impi_ver = required_version("stack_impi_ver")

local root = pathJoin(
    "/contrib/spack-stack",
    "spack-stack-" .. spack_ver,
    "envs",
    "ue-oneapi-" .. oneapi_ver,
    "install/modulefiles"
)

prepend_path("MODULEPATH", pathJoin(root, "Core"))

-- MPI module hierarchy validated on Ursa.
prepend_path("MODULEPATH", pathJoin(
    root,
    "intel-oneapi-mpi/2021.13-haww6b3/gcc/12.4.0"
))

load(pathJoin("stack-oneapi", oneapi_ver))
load(pathJoin("stack-intel-oneapi-mpi", impi_ver))

-- Reuse the existing version-controlled UPP dependencies.
load("upp_common")
