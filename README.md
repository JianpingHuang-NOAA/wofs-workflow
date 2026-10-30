# WoFS Workflow

Warn-on-Forecast System (WoFS) v1.0 workflow for
NOAA/NWS/Office of Modeling and Development (OMD).

## Reference Workflow

https://github.com/NOAA-EMC/rrfs-workflow

## Development Platform

NOAA RDHPCS Ursa

## Workflow Components

1. IC_PREP - Initial-condition preparation
2. BC_PREP - Boundary-condition preparation
3. WPS - WRF Preprocessing System
4. OBS_PREP - Radar (DBZ, VR) and satellite (CWP) Obs preparation for DA
5. GSI/EnKF - Data assimilation
6. FCST - WRF forecast
7. POST - Postprocessing
8. PLOT - Visualization

## Development Strategy

The workflow will be developed incrementally:

- Phase 1: IC_PREP and BC_PREP
- Phase 2: WPS and OBS_PREP
- Phase 3: GSI/EnKF and FCST
- Phase 4: POST and PLOT
- Phase 5: End-to-end testing and validation

## Repository Structure

- jobs/ - NCO-style J-job scripts
- scripts/ - Component execution scripts
- ush/ - Shared utilities
- parm/ - Configuration files and namelists
- fix/ - Static model data and references
- sorc/ - Source dependencies and build infrastructure
- ecf/ - ecFlow workflow definitions
- modulefiles/ - Platform-specific environments
- versions/ - Software dependency versions
- tests/ - Regression tests
- docs/ - Documentation

## Current Status

Under development. Not operationally validated.

Initial implementation focuses on IC_PREP and BC_PREP.

WPS has passed compilation testing on Ursa, but runtime
and numerical validation are pending.

GSI/EnKF, FCST, POST, and PLOT testing is pending.
