load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/contributed.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/wrf/WRFUserARW.ncl"

begin

; -------------------------------------------------------------------------------
; author:  David Dowell, October 2021
; Produce a NetCDF file containing perturbed (HRRR + GEFS member - GEFS mean) forecast fields.
; The NetCDF file that is created is in a format similar to the grib2 HRRR forecast file.
; -------------------------------------------------------------------------------

; -------------------------------------------------------------------------------

; variables that should be passed from shell script

hrrr_forecast = ""+HRRR_FCST
gefs_pert_time1 = ""+GEFSPERTTIME1
gefs_pert_time2 = ""+GEFSPERTTIME2
t1_string = ""+T1       ; time (hours) of first GEFS perturbation relative to HRRR forecast time
t2_string = ""+T2       ; time (hours) of second GEFS perturbation relative to HRRR forecast time
perturbed_hrrr_forecast = ""+PERT_HRRR

; -------------------------------------------------------------------------------

t1 = stringtointeger(t1_string)
t2 = stringtointeger(t2_string)

print("hrrr_forecast = " + hrrr_forecast)
print("gefs_pert_time1 = " + gefs_pert_time1)
print("gefs_pert_time2 = " + gefs_pert_time2)
print("t1 = " + t1)
print("t2 = " + t2)
print("perturbed_hrrr_forecast = " + perturbed_hrrr_forecast)

f_hrrr = addfile(hrrr_forecast, "r")
f_pert1 = addfile(gefs_pert_time1, "r")
f_pert2 = addfile(gefs_pert_time2, "r")
f_hrrr_pert = addfile(perturbed_hrrr_forecast, "c")

; WRF fields:
;   MU      perturbation dry air mass in column, Pa
;   P       perturbation pressure, Pa
;   P_HYD   hydrostatic pressure, Pa
;   PH      perturbation geopotential, m2/s2          (Time, bottom_top_stag, south_north, west_east)
;   U       x wind component, m/s                     (Time, bottom_top, south_north, west_east_stag)
;   V       y wind component, m/s                     (Time, bottom_top, south_north_stag, west_east)
;   T       perturbation potential temperature, K-t0  (Time, bottom_top, south_north, west_east)
;   QVAPOR  water vapor mixing ratio, kg/kg           (Time, bottom_top, south_north, west_east)
;           Note:  since water-vapor mixing ratio and specific humidity differ by at most a few percent, the
;           differences in units between QVAPOR (WRF Netcdf) and SPFH_P0_L105_GLC0 (grib2) will be ignored.
wrf_v = (/ "PH",     \
           "U",      \
           "V",      \
           "T",      \
           "QVAPOR" /)

; Perturbation inflation
scalemax = (/ 0.0, \
              0.7, \
              0.7, \
              0.5, \
              0.6 /)

; grib fields
;   PRES_P0_L105_GLC0  pressure, Pa              (lv_HYBL0, ygrid_0, xgrid_0)
;   HGT_P0_L105_GLC0   geopotential height, gpm  (lv_HYBL0, ygrid_0, xgrid_0)
;   UGRD_P0_L105_GLC0  u component of wind, m/s  (lv_HYBL0, ygrid_0, xgrid_0)
;   VGRD_P0_L105_GLC0  v component of wind, m/s  (lv_HYBL0, ygrid_0, xgrid_0)
;   TMP_P0_L105_GLC0   temperature, K            (lv_HYBL0, ygrid_0, xgrid_0)
;   SPFH_P0_L105_GLC0  specific humidity, kg/kg  (lv_HYBL0, ygrid_0, xgrid_0)
grib_v = (/ "HGT_P0_L105_GLC0",  \
            "UGRD_P0_L105_GLC0", \
            "VGRD_P0_L105_GLC0", \
            "TMP_P0_L105_GLC0",  \
            "SPFH_P0_L105_GLC0" /)

n_variables = 5

do v=0, n_variables-1

  print("processing variables:  " + wrf_v(v) + ", " + grib_v(v))

  if (wrf_v(v) .eq. "U") then
    stag1 = f_pert1->$wrf_v(v)$
    stag2 = f_pert2->$wrf_v(v)$
    dims = dimsizes(stag1)
    nz = dims(1)
    ny = dims(2)
    nx = dims(3)-1
    delete(dims)
    pert1 = new((/1,nz,ny,nx/), typeof(stag1))
    pert2 = new((/1,nz,ny,nx/), typeof(stag2))
    do i=0, nx-1
      pert1(:,:,:,i) = 0.5*stag1(:,:,:,i) + 0.5*stag1(:,:,:,i+1)
      pert2(:,:,:,i) = 0.5*stag2(:,:,:,i) + 0.5*stag2(:,:,:,i+1)
    end do
    delete(stag1)
    delete(stag2)

  else if (wrf_v(v) .eq. "V") then
    stag1 = f_pert1->$wrf_v(v)$
    stag2 = f_pert2->$wrf_v(v)$
    dims = dimsizes(stag1)
    nz = dims(1)
    ny = dims(2)-1
    nx = dims(3)
    delete(dims)
    pert1 = new((/1,nz,ny,nx/), typeof(stag1))
    pert2 = new((/1,nz,ny,nx/), typeof(stag2))
    do j=0, ny-1
      pert1(:,:,j,:) = 0.5*stag1(:,:,j,:) + 0.5*stag1(:,:,j+1,:)
      pert2(:,:,j,:) = 0.5*stag2(:,:,j,:) + 0.5*stag2(:,:,j+1,:)
    end do
    delete(stag1)
    delete(stag2)

  else if (wrf_v(v) .eq. "PH") then
    stag1 = f_pert1->$wrf_v(v)$
    stag2 = f_pert2->$wrf_v(v)$
    dims = dimsizes(stag1)
    nz = dims(1)-1
    ny = dims(2)
    nx = dims(3)
    delete(dims)
    pert1 = new((/1,nz,ny,nx/), typeof(stag1))
    pert2 = new((/1,nz,ny,nx/), typeof(stag2))
    do k=0, nz-1
      pert1(0,k,:,:) = 0.5*stag1(0,k,:,:) + 0.5*stag1(0,k+1,:,:)
      pert2(0,k,:,:) = 0.5*stag2(0,k,:,:) + 0.5*stag2(0,k+1,:,:)
    end do

;   Convert geopotential (m2/s2) to geopotential height (m)
    pert1 = 0.102 * pert1
    pert2 = 0.102 * pert2
    delete(stag1)
    delete(stag2)

  else
    pert1 = f_pert1->$wrf_v(v)$
    pert2 = f_pert2->$wrf_v(v)$
  end if
  end if
  end if

  scale = new((/nz/), typeof(pert1))
  do k=0, 24
    scale(k) = 1.0 + scalemax(v) * sqrt( (24.0-k) / 24.0)
  end do
  do k=25, nz-1
    scale(k) = 1.0
  end do

  print(scale)

  hrrr = f_hrrr->$grib_v(v)$
  pert_hrrr = hrrr

  if (t1 .eq. 0) then
    print("using perturbation at first time")
    do k=0, nz-1
      pert_hrrr(k,:,:) = pert_hrrr(k,:,:) + scale(k)*pert1(0,k,:,:)
    end do
  else
    w = int2flt(t2) / int2flt(t2 - t1)
    print("w = " + w)
    do k=0, nz-1
      pert_hrrr(k,:,:) = pert_hrrr(k,:,:) + scale(k) * (w*pert1(0,k,:,:) + (1.0-w)*pert2(0,k,:,:))
    end do
  end if

  f_hrrr_pert->$grib_v(v)$ = pert_hrrr

  delete(pert1)
  delete(pert2)
  delete(hrrr)
  delete(pert_hrrr)
  delete(scale)

end do

xlat = f_pert1->XLAT
xlong = f_pert1->XLONG
f_hrrr_pert->XLAT = xlat
f_hrrr_pert->XLONG = xlong
f_hrrr_pert@TRUELAT1 = f_pert1@TRUELAT1
f_hrrr_pert@TRUELAT2 = f_pert1@TRUELAT2
f_hrrr_pert@CEN_LAT = f_pert1@CEN_LAT
f_hrrr_pert@CEN_LON = f_pert1@CEN_LON
f_hrrr_pert@MOAD_CEN_LAT = f_pert1@MOAD_CEN_LAT
f_hrrr_pert@STAND_LON = f_pert1@STAND_LON

print("perturb_hrrr.ncl ran to completion")

end
