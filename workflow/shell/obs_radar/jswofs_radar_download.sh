#!/bin/bash
#SBATCH --job-name=wofs_radar_download
#SBATCH --partition=u1-compute
#SBATCH --ntasks=1
#SBATCH --mem=2G
#SBATCH --time=00:30:00

set -euo pipefail
: "${HOMEwofs:?Export HOMEwofs before submission}"
exec "$HOMEwofs/jobs/JWOFS_RADAR_DOWNLOAD" "$@"
