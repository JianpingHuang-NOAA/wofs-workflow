YYJJJ=22347


module purge
module load szip/2.1
module load intel/18.0.5.274
module load impi/2018.4.274
module load hdf5parallel
module load netcdf-hdf5parallel
module load pnetcdf/1.11.2
module load nco/4.9.1
module load cmake/3.16.1
module load hdf5/1.10.6
module load netcdf/4.7.0
module load wgrib2/2.0.8


#hour=0
hour=20

#while [[ $hour -le 19 ]];do
while [[ $hour -le 25 ]];do

HH=`printf %2.2i $hour`

wgrib2 hrrr.t12z.wrfprsf${HH}.grib2 -match ":TSOIL:" -grib tsoil.${HH}.grib2
wgrib2 hrrr.t12z.wrfprsf${HH}.grib2 -match ":SOILW:" -grib soilw.${HH}.grib2
wgrib2 hrrr.t12z.wrfnatf${HH}.grib2 -not_if "SOILW" -grib no_soilw.${HH}.grib2
cat no_soilw.${HH}.grib2 tsoil.${HH}.grib2 soilw.${HH}.grib2 > ${YYJJJ}120000${HH}

(( hour += 1 ))

done
