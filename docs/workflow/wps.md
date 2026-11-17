# WoFS v1.0 WPS and REAL Workflow

## 1. Overview

The WoFS v1.0 WPS workflow generates domain-specific
initial and lateral boundary conditions for the
36-member WoFS ensemble.

The workflow supports multiple simultaneous forecast
domains and follows the NCO-style job architecture.

## 2. Workflow architecture

The processing components are:

- GEOGRID
- UNGRIB_BC
- UNGRIB_IC
- METGRID_BC
- METGRID_IC
- REAL_BC
- REAL_IC

UNGRIB processing is shared across domains that use
identical input data and processing time windows.

GEOGRID, METGRID, and REAL are domain-specific.

Workflow dependencies:

    DOMAIN_SETUP
         |
         +-- GEOGRID ------------------+
         |                             |
    BC_PREP --> UNGRIB_BC --> METGRID_BC --> REAL_BC
                                       |
    IC_PREP --> UNGRIB_IC --> METGRID_IC --> REAL_IC

Both METGRID stages require the corresponding
UNGRIB outputs and domain-specific GEOGRID output.

## 3. Ensemble configuration

- Initial condition members: 36
- Boundary condition members: 18
- Horizontal grid spacing: 3 km
- METGRID atmospheric levels: 51
- METGRID soil temperature levels: 9
- METGRID soil moisture levels: 9

The intended boundary condition mapping for the
36-member forecast ensemble is:

    BC_MEMBER = ((MEMBER - 1) % 18) + 1

Forecast members 19-36 reuse boundary conditions
from members 01-18, respectively.

Only 18 canonical boundary condition files are
stored per domain in COM.

Independent working copies should be created during
forecast initialization when boundary conditions
may be modified.

The forecast initialization mapping remains to be
implemented in the downstream forecast workflow.

## 4. Configuration and installation

Main configuration:

    parm/wps/config.yaml

WPS namelist templates:

    parm/wps/namelist.wps.template
    parm/wps/namelist.ungrib.template

WRF namelist templates:

    parm/wrf/namelists.WOFS/

Version-controlled WPS tables:

    parm/wps/tables/

Runtime WPS tables:

    fix/WPS/WOFS/

The centralized FIX installer installs or verifies
the WoFS-specific WPS tables without modifying
the existing BC_PREP WPS tables.

    ./sorc/install_fix.sh

External geographic datasets and other required
FIX datasets must be available before execution.

## 5. Workflow execution

Example retrospective cycle:

    export HOMEwofs="$(pwd -P)"
    export DATAROOT=/path/to/runtime
    export COMROOT="$DATAROOT/com/wofs/v1.0"

    CDATE=2026110215

The DOMAIN_SETUP, IC_PREP, and BC_PREP products
must be available before their dependent stages.

Submit GEOGRID:

    ./workflow/shell/wps/submit_wofs_wps_geogrid.sh \
        "$CDATE" CSP NGP SE

Submit shared UNGRIB:

    ./workflow/shell/wps/submit_wofs_wps_ungrib.sh \
        "$CDATE" CSP NGP SE

After GEOGRID and UNGRIB complete, submit METGRID:

    ./workflow/shell/wps/submit_wofs_wps_metgrid.sh \
        "$CDATE" CSP NGP SE

After METGRID completes, submit REAL:

    ./workflow/shell/wps/submit_wofs_wps_real.sh \
        "$CDATE" CSP NGP SE

UNGRIB, METGRID, and REAL submission controllers
support optional stage selection:

    --stage BC
    --stage IC
    --stage ALL

The default is ALL.

The REAL submission controller skips members with
a valid completion marker and nonempty output file.

## 6. COM directory structure

    COMROOT/wofs.PDY/cyc/
        INPUT/
        WPS/
            UNGRIB/
                BC/mem01-mem18/
                IC/mem01-mem36/
        REGION/
            WPS/
                GEOGRID/
                BC/mem01-mem18/
                IC/mem01-mem36/
            REAL/
                BC/mem01-mem18/
                    wrfbdy_d01
                IC/mem01-mem36/
                    wrfinput_d01_ic

REGION identifies an individual forecast domain.

## 7. Output validation

Completion markers:

    GEOGRID_SUCCESS
    UNGRIB_SUCCESS
    METGRID_SUCCESS
    REAL_SUCCESS

METGRID publication validation checks:

- Required output files exist and are nonempty.
- Atmospheric dimension matches 51 levels.
- Soil temperature dimension matches 9 levels.
- Soil moisture dimension matches 9 levels.
- NUM_METGRID_SOIL_LEVELS matches 9.
- SOILT and SOILM variables exist.

REAL validates the atmospheric and soil dimensions
of every required METGRID input against the
member-specific WRF namelist.

REAL outputs are published only after successful
execution and output verification.

## 8. Three-domain retrospective execution

Validation cycle: 2026110215

Platform: NOAA Ursa

Domains:

- CSP: Central/Southern Plains
- NGP: Northern Great Plains
- SE: Southeast

Execution results:

| Component  | Successful tasks |
|------------|-----------------:|
| GEOGRID    |                3 |
| UNGRIB_BC  |               18 |
| UNGRIB_IC  |               36 |
| METGRID_BC |               54 |
| METGRID_IC |              108 |
| REAL_BC    |               54 |
| REAL_IC    |              108 |
| Total      |              381 |

Generated products:

- 3 GEOGRID files
- 342 shared BC intermediate files
- 36 shared IC intermediate files
- 1026 BC METGRID files
- 108 IC METGRID files
- 54 WRF boundary condition files
- 108 WRF initial condition files

All three domains completed REAL_BC and REAL_IC
successfully.

These results establish successful workflow execution
and output completeness. They do not establish
numerical equivalence with legacy WPS products.

## 9. Retrospective input considerations

During retrospective testing, the AWS HRRR native-level
files did not contain the complete nine-level soil
temperature and moisture profiles required by WoFS.

This resulted in incomplete METGRID soil fields and
REAL_BC failure.

The original WoFS boundary condition inputs containing
the required soil fields were restored. Subsequent
UNGRIB_BC, METGRID_BC, and REAL_BC processing completed
successfully.

Future retrospective input acquisition must ensure
that the complete soil profiles are available.

The METGRID publication validator was added after
the successful retrospective execution to prevent
incomplete soil profiles from receiving a completion
marker.

## 10. Remaining integration

- Radar observation preprocessing
- Satellite observation preprocessing
- GSI/EnKF data assimilation
- Forecast member initialization and BC mapping
- WRF forecast
- Post-processing
- Plotting
- End-to-end workflow integration
