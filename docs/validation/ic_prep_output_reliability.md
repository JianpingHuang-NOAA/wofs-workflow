# IC_PREP Output Reliability

## Phase A: Stale UPP output cleanup

Baseline workflow commit: bb64e21

UPP source commit:
170c09eccf76bc3885c17fdfb3537b2d902eefbb

UPP executable SHA256:
e0cae188fef2d5b3c3bcdf6d6decd98f6423657ddf5bcf3777e5fdce8fa9b302

### Problem

UPP opens parallel GRIB2 output files using MPI_MODE_CREATE
and MPI_MODE_WRONLY without explicitly truncating existing
files. Reruns can therefore retain stale trailing data.

### Workflow correction

Remove the following raw products immediately before UPP
execution:

- WRFNAT.GrbF
- WRFPRS.GrbF
- WRFTWO.GrbF
- WRFMSL.GrbF

The validated UPP source, executable, runtime environment,
and scientific parameter files remain unchanged.

### R4 regression experiment

- HRRRDAS initialization: 2026110214
- WoFS initialization: 2026110215
- Ensemble member: 26
- MPI tasks: 160
- Memory: 300 GB
- Slurm job ID: 26489343
- Job status: COMPLETED
- Exit code: 0:0

An oversized raw WRFNAT file was deliberately seeded using
the validated final WRFNAT product containing 1167 records.

| Product | Reference | Result |
|---------|-----------|--------|
| Raw WRFNAT | R3 | Bitwise identical |
| Raw WRFTWO | R3 | Bitwise identical |
| Processed WRFTWO | R3 | Bitwise identical |
| Final working WRFNAT | R3 | Bitwise identical |
| Final COM WRFNAT | R1 | Bitwise identical |

- Comparisons passed: 5
- Comparisons failed: 0
- Reference raw WRFNAT size: 601854682 bytes
- R4 raw WRFNAT size: 601854682 bytes

Final COM WRFNAT SHA256:

99d8b707d3e8c7839a9507bada5c2a2d8d82692741156f5b6de213ffeeca3799

### Conclusion

The workflow-level stale-output cleanup successfully
regenerated the expected raw and final GRIB2 products
without changing the scientific results for this test case.

Exact inventory validation, atomic COM publication,
and concurrent-execution protection will be addressed
in subsequent phases.
