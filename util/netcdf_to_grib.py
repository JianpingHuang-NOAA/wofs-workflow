#!/usr/bin/env python

import os, sys, time, math, pygrib
from numpy import *
import numpy as np
from netCDF4 import Dataset
from datetime import datetime, timedelta

netcdf_in = sys.argv[1]
netcdf_var = sys.argv[2]
grib_template = sys.argv[3]
grib_out = sys.argv[4]

print ('netcdf_in = ', netcdf_in)
print ('netcdf_var = ', netcdf_var)
print ('grib_template = ', grib_template)
print ('grib_out = ', grib_out)

if os.path.exists(netcdf_in):
  nc = Dataset(netcdf_in,'r')
  n = nc.variables[netcdf_var][:]
  nc.close()
else:
  print (netcdf_in, ' not found')
  sys.exit()

print ('shape, max of input netcdf variable = ', np.shape(n), np.max(n))

grbout = open(grib_out,'ab')
grbin = pygrib.open(grib_template)

for grb in grbin:
  k = grbin.tell()
  print ('k = ', k)
  print ('max value at level ', k, ' in template file:  ', grb['values'].max())
  print (grb.packingType)
  grb['values']=n[k-1,:,:]
  print ('max updated (perturbed) value:  ', grb['values'].max())
  msg = grb.tostring()
  grbout.write(msg)

grbin.close()

grbout.close()
