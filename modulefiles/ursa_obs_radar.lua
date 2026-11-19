whatis("Description: WoFS radar workflow controller on Ursa")
local version = os.getenv("python_ver")
if not version or version == "" then
    LmodError("Source versions/obs_radar.ver before loading this module")
end
load("python/" .. version)
