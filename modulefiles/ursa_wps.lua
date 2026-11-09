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
local jasper_ver = os.getenv("jasper_ver")
if not jasper_ver or jasper_ver == "" then
    LmodError("Missing jasper_ver; source versions/build.ver first")
end
load("jasper/" .. jasper_ver)

-- WPS build configuration
setenv("WRF_EM_CORE", "1")
setenv("WRF_NMM_CORE", "0")

-- Resolve Jasper installation using the module definition.
-- This avoids relying on environment changes during Lmod evaluation.
local jasper_module = "jasper/" .. jasper_ver
local jasper_info = capture(
    "module show " .. jasper_module .. " 2>&1"
)

local jasper_root = jasper_info:match(
    'prepend_path%("PATH","([^"]+)/bin"%)'
)

if not jasper_root then
    LmodError("Cannot determine Jasper installation from " .. jasper_module)
end

setenv("JASPER", jasper_root)
setenv("JASPERLIB", jasper_root .. "/lib64")
setenv("JASPERINC", jasper_root .. "/include")

-- Validate system libpng against the centralized build version.
local expected_png = os.getenv("wrf_libpng_ver")
if not expected_png or expected_png == "" then
    LmodError("Missing wrf_libpng_ver; source versions/build.ver first")
end

local actual_png = capture(
    "pkg-config --modversion libpng 2>/dev/null"
):gsub("%s+$", "")

if actual_png ~= expected_png then
    LmodError("libpng version mismatch: expected " ..
              expected_png .. ", found " .. actual_png)
end

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
