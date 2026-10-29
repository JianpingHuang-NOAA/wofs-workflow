;----------------------------------------------------------------------------------------------
;
; Compute PSFC
;
; David Dowell 2/23/2021
;
;----------------------------------------------------------------------------------------------

begin

print("compute_wrf_pressure.ncl")

infile = "./wrfout.nc"
f = addfile(infile, "w")

;--------------------------------

; pressure (Pa)
p = f->P
p = p + f->PB

; geopotential (m2 s-2)
gp = f->PH + f->PHB

; psfc initialization (dimensions, units)
psfc=f->MU

; psfc computation
g = 9.8

z0 = gp(0, 0, :, :) / g
z1 = 0.5 * (gp(0, 0, :, :)+gp(0, 1, :, :)) / g
z2 = 0.5 * (gp(0, 1, :, :)+gp(0, 2, :, :)) / g

w1 = (z0 - z2) / (z1 - z2)
w2 = 1.0 - w1

psfc(0, :, :) = w1*p(0, 0, :, :) + w2*p(0, 1, :, :)

print(max(psfc))
print(min(psfc))

psfc@description = "SFC PRESSURE"

f->PSFC = psfc

end
