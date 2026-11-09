-- ursa_wps.lua
-- NOAA Ursa environment for building and running WoFS WPS
-- Shares the validated WRF compiler, MPI, NetCDF, and HDF5 stack.

help([[
WoFS WPS build/runtime environment on NOAA Ursa.
Uses the common WoFS WRF environment and adds Jasper/PNG support.
]])

whatis("Name: ursa_wps")
whatis("Description: WoFS WPS build/runtime environment on Ursa")

-- Common WRF/WPS dependencies
load("ursa_wrf")

-- WPS GRIB2 compression dependency
load("jasper/2.0.32")

-- WPS build configuration
setenv("WRF_EM_CORE", "1")
setenv("WRF_NMM_CORE", "0")

-- Resolve Jasper from the module-provided library search path.
-- Do not use command -v jasper: an active Conda environment may
-- supply an unrelated Jasper executable.
local jasper_root = nil
local ld_paths = os.getenv("LD_LIBRARY_PATH") or ""

for path in string.gmatch(ld_paths, "[^:]+") do
    if path:match("/jasper%-2%.0%.32[^/]*/lib64$") then
        jasper_root = path:gsub("/lib64$", "")
        break
    end
end

if not jasper_root then
    LmodError("Cannot locate Jasper 2.0.32 library directory")
end

setenv("JASPER", jasper_root)
setenv("JASPERLIB", jasper_root .. "/lib64")
setenv("JASPERINC", jasper_root .. "/include")

-- Locate system libpng using pkg-config
local png_lib = capture("pkg-config --variable=libdir libpng 2>/dev/null"):gsub("%s+$", "")
local png_inc = capture("pkg-config --variable=includedir libpng 2>/dev/null"):gsub("%s+$", "")

if png_lib ~= "" then
    setenv("PNG_LIB", png_lib)
end

if png_inc ~= "" then
    setenv("PNG_INC", png_inc)
end

-- WPS configure expects the PNG installation prefix.
local png_prefix = capture("pkg-config --variable=prefix libpng 2>/dev/null"):gsub("%s+$", "")
if png_prefix ~= "" then
    setenv("PNG", png_prefix)
end
