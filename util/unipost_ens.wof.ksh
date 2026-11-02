#!/bin/ksh
#
# WoFS v1.0 IC_PREP - UPP compatibility wrapper
#
# The authoritative IC_PREP implementation is:
#   scripts/exwofs_ic_prep.sh
#
# Configuration is loaded from:
#   parm/ic_prep/config.yaml
#
# This wrapper does not define input/output paths,
# UPP parameters, or an itag file.
#

set -eu

# -------------------------------------------------------
# Required environment
# -------------------------------------------------------
: "${HOMEwofs:?HOMEwofs must be defined}"
: "${INIT_TIME:?INIT_TIME must be defined}"
: "${MEMBER:?MEMBER must be defined}"
: "${POST_WORK_DIR:?POST_WORK_DIR must be defined}"

# -------------------------------------------------------
# Configuration
# -------------------------------------------------------
export IC_PREP_CONFIG="${IC_PREP_CONFIG:-${HOMEwofs}/parm/ic_prep/config.yaml}"
export IC_PREP_STAGE="POST"

# -------------------------------------------------------
# Validate main processing script
# -------------------------------------------------------
EXSCRIPT="${HOMEwofs}/scripts/exwofs_ic_prep.sh"

if [[ ! -x "${EXSCRIPT}" ]]; then
    print -u2 "ERROR: IC_PREP exscript is missing or not executable:"
    print -u2 "  ${EXSCRIPT}"
    exit 1
fi

# -------------------------------------------------------
# Diagnostics
# -------------------------------------------------------
print "======================================================"
print " WoFS v1.0 IC_PREP - UPP compatibility wrapper"
print "======================================================"
print "HOMEwofs       = ${HOMEwofs}"
print "IC_PREP_CONFIG = ${IC_PREP_CONFIG}"
print "INIT_TIME      = ${INIT_TIME}"
print "MEMBER         = ${MEMBER}"
print "POST_WORK_DIR  = ${POST_WORK_DIR}"
print "======================================================"

# -------------------------------------------------------
# Run authoritative IC_PREP implementation
# -------------------------------------------------------
exec "${EXSCRIPT}"
