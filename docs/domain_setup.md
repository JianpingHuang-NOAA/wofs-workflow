# WoFS v1.0 DOMAIN_SETUP

## 1. Overview

DOMAIN_SETUP initializes the modeling domain for the
on-demand Warning-on-Forecast System (WoFS) workflow.

The implementation supports one to three independently
configured domains per submission on NOAA Ursa.

DOMAIN_SETUP generates:

- Domain-specific radar configuration.
- Geographical domain visualization.
- Domain-specific runtime configuration for downstream tasks.

The implementation follows the NCO-style workflow structure
and uses YAML-based configuration.

## 2. Workflow architecture

### Controller mode

    jwofs_domain_setup.sh
      -> jobs/JWOFS_DOMAIN_SETUP
        -> scripts/exwofs_domain_setup.sh
          -> ush/submit_domain_setup.py
            -> Submit enabled domain workers

### Worker mode

    jwofs_domain_setup.sh --worker
      -> jobs/JWOFS_DOMAIN_SETUP
        -> scripts/exwofs_domain_setup.sh
          -> ush/WoFS_grid_radars.py
          -> ush/generate_domain_runtime_config.py
          -> Validate generated products
          -> Publish products to COM

The controller validates the configuration and submits
independent Slurm jobs for the enabled domains.

Each worker processes one domain using an independent
temporary DATA directory.

The controller's successful completion indicates successful
submission, not completion of the domain workers.

## 3. Configuration

The primary configuration file is:

    parm/domain_setup/config.yaml

The YAML file defines:

- Event date and starting UTC hour.
- Enabled modeling domains.
- Domain center latitude and longitude.
- Domain width in kilometers.
- Python environment and Cartopy FIX data.
- Working-data, COM, and log directories.
- Slurm resource requirements.
- WPS timing and cycling parameters.
- Ensemble configuration.
- WRF and GSI/EnKF parameters.
- Observation-processing settings.
- Temporary DATA retention and COM publication.

### Example multi-domain configuration

    workflow:
      event: "20261102"
      start_hour: "15"
      region: CSP

    domains:
      - region: CSP
        enabled: true
        center_lat: 36.14885
        center_lon: -97.16102
        width_km: 900

      - region: NGP
        enabled: true
        center_lat: 44.00000
        center_lon: -100.00000
        width_km: 900

      - region: SE
        enabled: true
        center_lat: 33.00000
        center_lon: -85.00000
        width_km: 900

Set enabled to false to exclude a domain from submission.

Domain identifiers must be unique. A submission supports
a maximum of three enabled domains.

The limit applies to each controller submission, not to
the total number of active jobs across multiple submissions.

## 4. Python environment

DOMAIN_SETUP uses the shared WoFS Python runtime.

Install the environment from the repository root:

    bash sorc/install_wofs_python.sh

The default installation directory is:

    ${HOMEwofs}/python_env

Configure the YAML file using:

    python:
      env: ${HOMEwofs}/python_env
      cartopy_data_dir: ${HOMEwofs}/fix/cartopy

The Python environment is excluded from Git and must be
provisioned for a new installation.

### Validated Python packages

| Package | Version |
|---------|---------|
| Python | 3.11.12 |
| PyYAML | 6.0.2 |
| NumPy | 2.2.5 |
| SciPy | 1.15.2 |
| netCDF4 | 1.7.4 |
| cftime | 1.6.5 |
| PyProj | 3.7.2 |
| PyGRIB | 2.1.8 |
| Matplotlib | 3.10.1 |
| Cartopy | 0.25.0 |
| Shapely | 2.1.2 |
| PyShp | 2.3.1 |

The package requirements and version metadata are maintained
in sorc/requirements_wofs.txt and versions/run.ver.

## 5. Cartopy geographical FIX data

The legacy Basemap dependency has been replaced with
PyProj and Cartopy.

Natural Earth geographical datasets are provisioned locally
to avoid downloading data from compute nodes.

For a new installation, provision the Cartopy data from
a login node with network access:

    export HOMEwofs="$(pwd -P)"
    export WOFS_PYTHON="${HOMEwofs}/python_env/bin/python3"

    bash sorc/install_cartopy_data.sh \
        "${HOMEwofs}/fix/cartopy"

The geographical FIX data include seven standard plotting
features at 110m, 50m, and 10m resolutions.

The geographical data checksum manifest is:

    parm/cartopy/cartopy_fix.sha256

The radar selection preserves the legacy projection and
domain-selection calculations. Cartopy is used for the
domain visualization.

## 6. Slurm execution

### Configuration validation without submission

From the repository root:

    cd workflow/shell/domain_setup

    bash jwofs_domain_setup.sh --dry-run

### Submit DOMAIN_SETUP

    sbatch jwofs_domain_setup.sh

The controller submits one independent worker job for each
enabled domain.

### Alternative configuration file

    sbatch jwofs_domain_setup.sh \
        --config /shared/path/config.yaml

Alternative configuration files must be accessible from
both login and compute nodes.

Do not modify an active configuration file while its
associated domain jobs are queued or running.

### Monitor execution

    squeue -u "$USER"

    sacct -X -j JOBID \
        --format=JobID,JobName%25,State,ExitCode,Elapsed

Check both the controller and worker job statuses.

## 7. Working-data management

The domain working-data parent directory is:

    ${DATAROOT}/domain_setup/${PDY}/${cyc}/${region}

Each worker creates a unique temporary directory:

    ${DOMAIN_WORK_ROOT}/job.XXXXXXXX

The temporary directory is exported as DATA and is used
for domain product generation.

The persistent domain parent directory contains a lock
file that prevents simultaneous DOMAIN_SETUP processing
for the same domain and cycle.

### Temporary DATA retention

The YAML runtime section controls publication and cleanup:

    runtime:
      sendcom: true
      keepdata: false

These settings are translated into SENDCOM and KEEPDATA.

| SENDCOM | KEEPDATA | Successful execution behavior |
|---------|----------|-------------------------------|
| YES | NO | Publish products and remove temporary DATA |
| YES | YES | Publish products and retain temporary DATA |
| NO | NO | Retain temporary DATA without publication |
| NO | YES | Retain temporary DATA without publication |

Temporary DATA is retained when processing or publication
fails.

Cleanup occurs only after successful processing and
verification of the published COM products.

The cleanup implementation removes the known DOMAIN_SETUP
products and then removes the empty temporary directory.
It does not recursively delete the domain parent directory.

## 8. COM products

The default COM directory structure is:

    ${DATAROOT}/com/wofs/v1.0/
      wofs.${PDY}/${cyc}/
        INPUT/
        CSP/
        NGP/
        SE/

INPUT contains shared IC_PREP and BC_PREP products.

Each enabled domain receives three DOMAIN_SETUP products:

    radars_${PDY}_${region}.sh
    realtime.cfg.${PDY}.${region}
    WOFS_domain_${PDY}_${region}.png

For example:

    wofs.20261102/15/CSP/
      radars_20261102_CSP.sh
      realtime.cfg.20261102.CSP
      WOFS_domain_20261102_CSP.png

The runtime configuration contains persistent COM paths
for downstream processing rather than temporary
DOMAIN_SETUP working-data paths.

The planned domain-specific downstream COM directories
include:

    WPS/IC/
    WPS/BC/
    OBS/RADAR/
    OBS/SATELLITE/
    DA/
    FCST/
    POST/
    PLOT/

These directories are reserved for downstream workflow
components and are not initialized by DOMAIN_SETUP.

COM publication is serialized for each domain.
Individual products are copied, verified, and renamed
into their final locations.

Publication is atomic for each individual file, not
for the complete three-file product set.

## 9. Logs

Worker logs are stored under:

    ${DATAROOT}/logs/wofsv1.0/domain_setup/

Example:

    domain_setup_CSP_JOBID.out
    domain_setup_CSP_JOBID.err

The logs contain:

- Domain configuration.
- Temporary DATA directory.
- Python runtime information.
- Product-generation results.
- COM publication results.
- Temporary DATA cleanup or retention status.

Controller logs use the Slurm output configuration
associated with the submission.

## 10. Validation results

### Scientific validation

The PyProj/Cartopy radar-selection implementation was
validated against the legacy Basemap implementation
for the CSP reference domain.

The radar configuration contained 20 selected radars
and was byte-identical to the legacy reference.

The generated geographical visualization is not
expected to be byte-identical because the plotting
library has changed.

### Multi-domain execution

Validation cycle: 2026110215

| Domain | Latitude | Longitude | Width (km) |
|--------|----------|-----------|------------|
| CSP | 36.14885 | -97.16102 | 900 |
| NGP | 44.00000 | -100.00000 | 900 |
| SE | 33.00000 | -85.00000 | 900 |

Slurm validation results:

| Job ID | Task | State | Exit code | Elapsed |
|--------|------|-------|-----------|---------|
| 26686276 | Controller | COMPLETED | 0:0 | 2 sec |
| 26686277 | CSP | COMPLETED | 0:0 | 7 sec |
| 26686278 | NGP | COMPLETED | 0:0 | 7 sec |
| 26686279 | SE | COMPLETED | 0:0 | 7 sec |

All three domain workers successfully published their
products and removed their temporary DATA directories
with KEEPDATA=NO.

### Temporary DATA retention

A separate CSP execution with KEEPDATA=YES retained:

    job.uDOkYg34/
      radars_20261102_CSP.sh
      realtime.cfg.20261102.CSP
      WOFS_domain_20261102_CSP.png

All three expected products were present.

### Python installation

The repository-local Python environment passed all
package, native-library, geographical-library, and
dependency-consistency checks.

### Implementation reference

    Branch: feature/domain-setup
    Commit: afdd17f

## 11. Integration requirements and limitations

DOMAIN_SETUP product generation and multi-domain
submission have been validated.

The complete comparison of generated runtime
configuration parameters against the legacy runtime
configuration has not yet been confirmed.

The runtime-directory initialization and resource-staging
utilities are retained for downstream integration.
They are no longer executed by DOMAIN_SETUP.

Domain-specific WPS processing, including geogrid,
IC processing, and BC processing, remains to be implemented.

Radar and satellite observation preprocessing for
data assimilation also remains to be implemented.

The current development resource links and FIX
installation must be provisioned appropriately for
a production deployment.

The configuration should not be changed or republished
for a domain while dependent processing is active.

## 12. WoFS v1.0 development roadmap

1. IC_PREP - completed and validated.
2. BC_PREP - completed and validated.
3. DOMAIN_SETUP - implementation completed and validated
   within the scope described above.
4. Domain-specific WPS IC and BC processing.
5. Radar and satellite observation preprocessing.
6. GSI/EnKF data assimilation.
7. WRF ensemble forecast.
8. POST processing.
9. PLOT processing.
10. End-to-end workflow integration.

