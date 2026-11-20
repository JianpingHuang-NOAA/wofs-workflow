import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as P
import numpy as N
import time as timeit
import sys
from optparse import OptionParser
from pyproj import Proj
import cartopy.crs as ccrs
from cartopy.io import shapereader
from matplotlib.patches import Circle
import os

from pathlib import Path
from datetime import datetime
import re

# HRRR Grid description

background_grid = (22.5, -105., 45., -75.)

#
# SOUTHEAST
# upper left:  40.3191, -98.4864
# upper right:  37.6356, -75.9925
# lower right:  23.3686, -80.2597
# lower left:  25.522, -98.932
#
# SOUTH
# upper left:  38.757, -108.312
# upper right:  37.9824, -85.7724
# lower right:  23.4201, -88.3926
# lower left:  24.0398, -107.04
#
# CENTRAL
# upper left:  43.954, -107.949
# upper right:  42.9414, -83.6839
# lower right:  28.3025, -86.8428
# lower left:  29.1194, -106.662
#
# NORTHEAST
# upper left:  49.2485, -92.1585
# upper right:  45.138, -67.0883
# lower right:  31.0891, -73.3912
# lower left:  34.4401, -93.912

HRRR_grid = { "SE": { 'grid_lats': ( 25.522,  23.3686,  37.6356,  40.3191),
                      'grid_lons': (-98.932, -80.2597, -75.9925, -98.4864),
                      'boundary_zone': ( 0.,  100., 200.),
                      'alphas':        ( 0.2, 0.4,  0.6),
                    },
              "SC": { 'grid_lats': (  24.0398, 23.4201,  37.9824,   38.757),
                      'grid_lons': (-107.04,  -88.3926, -85.7724, -108.312),
                      'boundary_zone': ( 0.,  100., 200.),
                      'alphas':        ( 0.2, 0.4,  0.6),
                    },
              "CP": { 'grid_lats': (  29.1194, 28.3025,  42.9414,   43.954),
                      'grid_lons': (-106.662, -86.8428, -83.6839, -107.949),
                      'boundary_zone': ( 0.,  100., 200.),
                      'alphas':        ( 0.2, 0.4,  0.6),
                    },
              "NP": { 'grid_lats': (  36.4470, 34.8041,  47.9372,   49.9149),
                      'grid_lons': (-106.219, -81.2196, -76.8972, -107.4062),
                      'boundary_zone': ( 0.,  100., 200.),
                      'alphas':        ( 0.2, 0.4,  0.6),
                    },
              "NE": { 'grid_lats': (  35.2481,  31.5255,  44.2604,  48.7421),
                      'grid_lons': ( -96.3312, -72.4002, -66.5531, -95.2896),
                      'boundary_zone': ( 0.,  100., 200.),
                      'alphas':        ( 0.2, 0.4,  0.6),
                    }
             }


_station_file         = 'conus2015.tbl'
_radar_file           = 'nexrad_stations.txt'
_default_WOFS_size   = 900.   # width of domain in km
#_default_WOFS_size   = 1005.   # width of domain in km
_default_grid_center  = "TCL"
_default_max_radars   = 7      # Not used....
radar_buf_dis         = 100000.

# constants

__r_earth              = 6367000.0
__truelat1, __truelat2 = 38.5, 38.5

# Legacy Basemap default spherical Earth radius.
# Preserve separately from the domain corner radius.
__projection_radius = 6370997.0
__projection_lon_0 = -97.5

#==================================================================================
def read_radar_location_file(_radar_file):

    f = open(_radar_file, 'r')

    header1 = f.readline()

    radar_locations_dict = {}

    one_sixty = 1./ 60.

    for line in f:
        col = line.split()
        lat = float(col[2]) + one_sixty*(float(col[3]) + one_sixty*float(col[4]))
        lon = float(col[5]) + one_sixty*(float(col[6]) + one_sixty*float(col[7]))
        alt = 0.001 * float(col[8])
        radar_locations_dict[col[0]] = (lat, -lon, alt)

    return radar_locations_dict

#==================================================================================
def read_radar_location_file2(_radar_file):

    f = open(_radar_file, 'r')

    #header1 = f.readline()

    radar_locations_dict = {}

    one_sixty = 1./ 60.

    for line in f:
        col = line.split()
        lat = float(col[-5])
        lon = float(col[-4])
        alt = 0.0003048 * float(col[-3])
        radar_locations_dict[col[1]] = (lat, lon, alt)

    return radar_locations_dict

#==================================================================================
def read_sfc_station_file(_station_file):

    f = open(_station_file, 'r')

    sfc_stations_dict = {}

    for line in f:
        col = line.split()
        sfc_stations_dict[col[0]] = (0.01*float(col[5]), 0.01*float(col[6]))

    return sfc_stations_dict

#==================================================================================

def create_projection(lat_0):
    """Scientific projection matching legacy Basemap."""

    return Proj(
        proj="lcc",
        lat_0=lat_0,
        lon_0=__projection_lon_0,
        lat_1=__truelat1,
        lat_2=__truelat2,
        R=__projection_radius,
        units="m",
    )


def create_map_crs(lat_0):
    """Cartopy projection matching the scientific projection."""

    globe = ccrs.Globe(
        semimajor_axis=__projection_radius,
        semiminor_axis=__projection_radius,
        ellipse=None,
    )

    return ccrs.LambertConformal(
        central_longitude=__projection_lon_0,
        central_latitude=lat_0,
        standard_parallels=(
            __truelat1,
            __truelat2,
        ),
        globe=globe,
    )


def add_map_background(ax):
    """Read local geographical datasets without downloads."""

    default_dir = (
        Path(__file__).resolve().parents[1]
        / "fix" / "cartopy"
    )

    data_dir = Path(
        os.environ.get(
            "CARTOPY_DATA_DIR",
            str(default_dir),
        )
    ).resolve()

    datasets = [
        ("physical", "coastline", 0.6),
        ("cultural", "admin_0_boundary_lines_land", 0.6),
        ("cultural", "admin_1_states_provinces_lines", 0.4),
    ]

    for category, name, linewidth in datasets:

        shp = (
            data_dir
            / "shapefiles"
            / "natural_earth"
            / category
            / f"ne_50m_{name}.shp"
        )

        for suffix in (".shp", ".shx", ".dbf", ".prj"):
            required = shp.with_suffix(suffix)

            if not required.is_file():
                raise FileNotFoundError(
                    f"Missing Cartopy fix file: {required}"
                )

        reader = shapereader.Reader(str(shp))

        try:
            geometries = list(reader.geometries())
        finally:
            reader.close()

        ax.add_geometries(
            geometries,
            crs=ccrs.PlateCarree(),
            facecolor="none",
            edgecolor="black",
            linewidth=linewidth,
        )


#//////////////////////////////////////////// MAIN ///////////////////////////////////////////////

print('\n------------------------------------------------------------------------------------\n')
print('  ==> BEGIN PROGRAM WOFS Grid and Radars')
print('\n------------------------------------------------------------------------------------\n')

# parse command line

parser = OptionParser()
parser.add_option(      "--latlon", dest="latlon", type="float", default=None, nargs = 2, help = "Latlon of grid centerpoint")
parser.add_option("-w", "--width",   dest="width",   type="int",    default=None, help = "Size of WOFS domain in km")
parser.add_option("-p", "--plot",    dest="plot",                   default=False, help = "Boolean flag to interactively plot domain", action="store_true")
parser.add_option("-r", "--region",  dest="region",  type="string", default="CP", help="Background HRRR region:  Valid regions are CP, NE, SE, SC, default is CP")
parser.add_option("-d", "--hwtdd",  dest="hwtdd",   action="store_true",    default=False,     help="Flag to enable plot of HWT daily domain in background")

parser.add_option("--event", dest="event", type="string",
                  help="Event date in YYYYMMDD format")
parser.add_option("--start-hour", dest="start_hour", type="string",
                  help="Starting UTC hour in HH format")
parser.add_option("--output-dir", dest="output_dir", type="string",
                  default=".", help="Domain-specific output directory")
parser.add_option("--station-dir", dest="station_dir", type="string",
                  default=str(Path(__file__).resolve().parents[1] /
                              "parm" / "domain_setup"),
                  help="Station database directory")

(options, args) = parser.parse_args()

if not options.event or not re.fullmatch(r"[0-9]{8}", options.event):
    parser.error("--event must be YYYYMMDD")

try:
    datetime.strptime(options.event, "%Y%m%d")
except ValueError:
    parser.error("Invalid event date")

if not options.start_hour or not re.fullmatch(
        r"(?:[01][0-9]|2[0-3])", options.start_hour):
    parser.error("--start-hour must be between 00 and 23")

if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", options.region):
    parser.error("Invalid region identifier")

if options.latlon is not None:
    lat, lon = options.latlon
    if not (-90 < lat < 90 and -180 <= lon <= 180):
        parser.error("Invalid domain center coordinates")

if options.width is not None and options.width <= 0:
    parser.error("Domain width must be positive")

output_dir = Path(options.output_dir).resolve()
output_dir.mkdir(parents=True, exist_ok=True)

station_dir = Path(options.station_dir).resolve()
_station_file = str(station_dir / "conus2015.tbl")
_radar_file = str(station_dir / "nexrad_stations.txt")

if options.latlon == None:
    print("\n  !!!!! ERROR:  !!! FORGOT to put the latlon of the WOFS grid center on command line !!!\n ")
    parser.print_help()
    print
    sys.exit(1)
else:
    print("\n  WOFS grid center location supplied, using the input value of %f %f \n " % (options.latlon[0], options.latlon[1]))
    lat_c = options.latlon[0]
    lon_c = options.latlon[1]

if options.width == None:
    print("\n  No WOFS grid width supplied, using the default of %d km \n " % _default_WOFS_size)
    WOFS_size = 1000. * _default_WOFS_size
else:
    print("\n  WOFS grid width supplied, using the input value of %d km \n " % options.width)
    WOFS_size = 1000. * options.width

x_nudge, y_nudge = 0.0, 0.0

print('\n------------------------------------------------------------------------------------\n')
print('  ==> HRRRe grid location is %s \n' % options.region)
print('\n------------------------------------------------------------------------------------\n')

print('\n------------------------------------------------------------------------------------\n')
print('  ==> Reading in data base information\n')

stations = read_sfc_station_file(_station_file)

print("  Read in sfc station file successfully\n")

radars = read_radar_location_file2(_radar_file)

print("  Read in radar file successfully\n")

print('------------------------------------------------------------------------------------\n')


# Scientific coordinate transformation.
map = create_projection(lat_c)

# Matching Cartopy visualization projection.
map_crs = create_map_crs(lat_c)

fig, ax1 = P.subplots(
    1,
    1,
    figsize=(7, 7),
    subplot_kw={"projection": map_crs},
)

# Preserve the legacy projected background extent.
xmin, ymin = map(-122.7195, 21.13812)
xmax, ymax = map(-60.84946, 47.85785)

ax1.set_xlim(xmin, xmax)
ax1.set_ylim(ymin, ymax)

add_map_background(ax1)

print("The lat_c and lon_c are: %s %s" % (lat_c, lon_c))

##Plot HRRR grid with boundary strips....
#
#x0, y0 = map(HRRR_grid[options.region]['grid_lons'],HRRR_grid[options.region]['grid_lats'])
#
#for n, item in enumerate(HRRR_grid[options.region]['boundary_zone']):
#
#    x, y = N.array(x0), N.array(y0)
#
#    strip = item*1000.
#
#    x[0] = x[0] + strip
#    x[1] = x[1] - strip
#    x[2] = x[2] - strip
#    x[3] = x[3] + strip
#
#    y[0] = y[0] + strip
#    y[1] = y[1] + strip
#    y[2] = y[2] - strip
#    y[3] = y[3] - strip
#
#
#    x = N.append(x,x[0])
#    y = N.append(y,y[0])
#
#    P.fill(x, y, color='b', alpha=HRRR_grid[options.region]['alphas'][n])

#Plot WOFS grid - create Lambert conformal map based on width and height of domain and center point

x0, y0 = map(lon_c, lat_c)

lon_c, lat_c = map(x0+0, y0+0, inverse=True)

if x_nudge > 0 or y_nudge > 0:
   print("  Grid center moved, new center is is located at %f  %f\n" % (lat_c, lon_c))

# Convert to radians to create corners

lat_c, lon_c = N.deg2rad(lat_c), N.deg2rad(lon_c)

glat = N.zeros(5)
glon = N.zeros(5)

glat[0] = lat_c - 0.5*(WOFS_size) / __r_earth
glat[1] = lat_c + 0.5*(WOFS_size) / __r_earth
glat[2] = lat_c + 0.5*(WOFS_size) / __r_earth
glat[3] = lat_c - 0.5*(WOFS_size) / __r_earth
glat[4] = lat_c - 0.5*(WOFS_size) / __r_earth

glon[0] = lon_c - 0.5*(WOFS_size) / (__r_earth * N.cos(glat[0]))
glon[1] = lon_c - 0.5*(WOFS_size) / (__r_earth * N.cos(glat[1]))
glon[2] = lon_c + 0.5*(WOFS_size) / (__r_earth * N.cos(glat[2]))
glon[3] = lon_c + 0.5*(WOFS_size) / (__r_earth * N.cos(glat[3]))
glon[4] = lon_c - 0.5*(WOFS_size) / (__r_earth * N.cos(glat[4]))

glon = N.rad2deg(glon)
glat = N.rad2deg(glat)

xg, yg = map(glon, glat)

ax1.fill(
    xg, yg,
    linewidth=2,
    color="g",
    alpha=0.2,
    transform=map_crs,
)

#P.title("27 April 2011 \n 100 km bounding boxes \n Radars (150 km range rings)", fontsize=18)
P.title("Radar locations within experimental WoFS grid shown as blue dots with 150-km range rings \n \n \n SYSTEM STATUS: RUNNING", y=-0.25, fontsize=10)

title = ("3-km HRRRE background and nested experimental WoFS grid")

fig.suptitle(title, y=0.8, fontsize=14)

# search for radars inside the grid

radar_name= []
radar_lon = []
radar_lat = []
radar_alt = []

for key in radars:
    x, y = map(radars[key][1], radars[key][0])
    #if x <= max(xg) and x >= min(xg) and y<= max(yg) and y >= min(yg):
    if x-radar_buf_dis <= max(xg) and x+radar_buf_dis >= min(xg) and \
       y-radar_buf_dis <= max(yg) and y+radar_buf_dis >= min(yg):
        radar_lon.append(radars[key][1])
        radar_lat.append(radars[key][0])
        radar_alt.append(radars[key][2])
        radar_name.append(key)

        circle1 = Circle(
            (x, y),
            150000.,
            color="gray",
            linewidth=1,
            fill=False,
            transform=map_crs,
        )

        ax1.add_patch(circle1)

        ax1.scatter(
            x, y,
            s=3,
            marker="o",
            color="blue",
            transform=map_crs,
        )


# *** Added by Brett Roberts 2019-04-24 ***
# Attempts to plot red polygon for today's HWT daily domain when -d is used
if options.hwtdd:
#    try:
     import datetime
     import json
     import os

     dir_json = '/home/wofuser/WOFS_grid_radar/sfe_sectors/'
     today_yyyymmdd = datetime.datetime.utcnow().strftime("%Y%m%d")

     path_json = os.path.join(dir_json, 'hwt_primary.' + today_yyyymmdd + '.json')

     corners = json.loads( open( path_json , "rb" ).read() ).get( "corners" )

     print (corners)

     hwtdd_lats = [cp[0] for cp in corners]
     hwtdd_lons = [cp[1] for cp in corners]

     hwtx, hwty = map( hwtdd_lons, hwtdd_lats )
     hwtxy = N.array( list(zip(hwtx, hwty)) )
     hwtpoly = matplotlib.patches.Polygon( hwtxy , fill=False, edgecolor='red', linewidth=2 )
     ax1.add_patch(hwtpoly)
#    except Exception:
#        print('Plotting of HWT daily domain failed; JSON file may not exist in ' + str(dir_json))

event = options.event
region = options.region
fout = output_dir / f"radars_{event}_{region}.csh" 

# Write out csh file.....

outfile = open(fout, 'w')
outfile.write("#!/bin/csh\n#\n")

nradars = len(radar_name)

outfile.write("setenv num_rad %d\n" % nradars)

outfile.write("set rad_lon = ( %s )\n" % (' '.join([str(x) for x in radar_lon])))

outfile.write("set rad_lat = ( %s )\n" % (' '.join([str(x) for x in radar_lat])))

outfile.write("set rad_alt = ( %s )\n" % (' '.join([str(round(x,7)) for x in radar_alt])))

outfile.write("set rad_name = ( %s )\n" % (' '.join([x for x in radar_name])))

outfile.write("setenv cen_lat %f\n" % N.rad2deg(lat_c))

outfile.write("setenv cen_lon %f\n" % N.rad2deg(lon_c))

outfile.write("setenv lat_ll %f\n" % glat[0])
outfile.write("setenv lat_ur %f\n" % glat[1])
outfile.write("setenv lon_ll %f\n" % glon[0])
outfile.write("setenv lon_ur %f\n" % glon[2])

outfile.write("setenv region %s\n" % region)
outfile.write("setenv start_hr %s\n" % options.start_hour)

#outfile.write("setenv year %s\n" % date.year)

outfile.close()

print("\n  Found %d radars within domain\n" % nradars)

fout2 = output_dir / f"WOFS_domain_{event}_{region}.png"

fig.savefig(fout2)
P.close(fig)

print('\n------------------------------------------------------------------------------------\n')
print("\n  Wrote out plot file with name %s\n" % fout2)
print("\n  Wrote out radar file to be sourced with name %s\n" % fout)
print('\n------------------------------------------------------------------------------------\n')
print('  ==> END PROGRAM WOFS Grid and Radars')
print('\n------------------------------------------------------------------------------------\n')


