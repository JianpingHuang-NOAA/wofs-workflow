#!/bin/bash
#SBATCH -J wofs_domain_setup
#SBATCH -p u1-compute
#SBATCH -q debug
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:10:00
#SBATCH -o wofs_domain_setup_%j.out
#SBATCH -e wofs_domain_setup_%j.err

set -euo pipefail

: "${HOMEwofs:?HOMEwofs must be set}"

export HOMEwofs

export DOMAIN_SETUP_CONFIG="${DOMAIN_SETUP_CONFIG:-${HOMEwofs}/parm/domain_setup/config.yaml}"

# Load component runtime versions.
source "${HOMEwofs}/versions/domain_setup.ver"

# Initialize the Ursa module environment.
module purge
module use "${HOMEwofs}/modulefiles"
module load "${wofs_modulefile}"

# Initialize the common WoFS Python runtime.
source "${HOMEwofs}/ush/load_wofs_python.sh"

# Execute the DOMAIN_SETUP J-job.
exec /bin/bash "${HOMEwofs}/jobs/JWOFS_DOMAIN_SETUP"

