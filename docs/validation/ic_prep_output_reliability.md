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

## Phase B: Exact GRIB2 inventory validation

Implementation baseline: e82a69a

### Configuration

The following configurable inventory expectations are
defined for the validated WoFS v1.0 UPP baseline:

| Configuration key | Expected records |
|-------------------|-----------------:|
| expected_raw_wrfnat_fields | 1000 |
| expected_raw_wrftwo_fields | 169 |
| expected_final_wrftwo_fields | 167 |
| expected_final_wrfnat_fields | 1167 |

The configuration loader validates positive integer
values and inventory consistency. Older YAML files
receive the validated baseline defaults.

The previous expected_num_fields setting is retained
for compatibility but no longer controls POST inventory
validation.

### Runtime validation

Exact inventory checks are performed for:

1. Raw WRFNAT.
2. Raw WRFTWO.
3. Processed WRFTWO.
4. Final working-directory WRFNAT.
5. Final COM WRFNAT.

Inventory mismatches terminate IC_PREP with a nonzero
exit code.

### Configuration regression

Permanent test:
tests/check_ic_prep_inventory_config.sh

- Passed: 10
- Failed: 0

### R5: Positive runtime regression

- HRRRDAS initialization: 2026110214
- WoFS initialization: 2026110215
- Ensemble member: 26
- MPI tasks: 160
- Memory request: 300G
- Slurm job ID: 26490986
- Slurm state: COMPLETED
- Exit code: 0:0

All five inventory checks passed.

All five bitwise comparisons against R1 and R3 passed.

Final COM WRFNAT SHA256:

99d8b707d3e8c7839a9507bada5c2a2d8d82692741156f5b6de213ffeeca3799

### R6: Negative runtime regression

- HRRRDAS initialization: 2026110214
- Ensemble member: 26
- MPI tasks: 160
- Memory request: 300G
- Slurm job ID: 26490987
- Slurm state: FAILED
- Exit code: 1:0

The configured raw WRFNAT expectation was deliberately
changed from 1000 to 1001 records, with the final
WRFNAT expectation changed to 1168 for consistency.

The workflow correctly detected:

- Expected raw WRFNAT records: 1001
- Actual raw WRFNAT records: 1000

IC_PREP terminated before publishing the COM product.
No successful-completion message was emitted.

### Validation summary

| Test group | Passed | Failed |
|------------|-------:|-------:|
| Configuration tests | 10 | 0 |
| R5 positive runtime checks | 11 | 0 |
| R6 negative runtime checks | 6 | 0 |
| Total | 27 | 0 |

### Conclusion

Exact inventory validation preserves the bitwise
reproducibility of the validated WoFS v1.0 scientific
baseline and correctly rejects the tested inventory
mismatch.

Atomic COM publication and concurrent-execution
protection remain subsequent development phases.

Record-count validation does not establish complete
GRIB2 content integrity.

## Phase C: Atomic COM publication

Implementation baseline: 764f5df

### Implementation

The direct COM copy is replaced by the reusable
publication function in:

ush/publish_ic_prep_grib2.sh

The publication function:

1. Creates a unique hidden temporary file in the
   destination COM directory.
2. Copies the validated source product.
3. Preserves source file mode bits.
4. Validates the exact GRIB2 inventory.
5. Verifies byte-for-byte identity with the source.
6. Atomically renames the temporary file to the
   final COM filename.
7. Removes temporary files on handled failures.

Explicit failure handling is provided for temporary
file creation, copying, permission changes,
inventory validation, byte comparison and rename.

The existing COM overwrite behavior is preserved.

### Permanent synthetic regression

Test:

tests/check_ic_prep_atomic_publication.sh

- Passed: 23
- Failed: 0

The tests cover initial publication, replacement,
missing and empty sources, incorrect inventories,
simulated filesystem operation failures,
identical source and destination, preservation
of existing COM products and temporary-file cleanup.

### R7: Full IC_PREP regression

- HRRRDAS initialization: 2026110214
- WoFS initialization: 2026110215
- Ensemble member: 26
- MPI tasks: 160
- Memory request: 300G
- Slurm job ID: 26492648
- Slurm state: COMPLETED
- Exit code: 0:0

Validated GRIB2 inventories:

| Product | Records |
|---------|--------:|
| Raw WRFNAT | 1000 |
| Raw WRFTWO | 169 |
| Processed WRFTWO | 167 |
| Final working WRFNAT | 1167 |
| Temporary COM WRFNAT | 1167 |
| Final COM WRFNAT | 1167 |

All five bitwise comparisons against R1 and R3
passed.

Final COM WRFNAT SHA256:

99d8b707d3e8c7839a9507bada5c2a2d8d82692741156f5b6de213ffeeca3799

R7 exercised the initial atomic publication helper
before the final defensive error-handling changes.

### R8: Atomic replacement

An existing 1000-record raw WRFNAT product was
replaced by a validated 1167-record final product.

The replacement was bitwise identical to R1.

### R9: Invalid inventory rejection

The expected inventory was deliberately set to
1168 records for a valid 1167-record candidate.

The temporary product was rejected before rename.

The existing COM product remained unchanged and
bitwise identical to R1.

### Hardened R8/R9 regression

- Slurm job ID: 26493754
- Slurm state: COMPLETED
- Exit code: 0:0
- Passed: 13
- Failed: 0

The hardened publication helper passed all actual
GRIB2 publication checks.

### Validation summary

| Test group | Passed | Failed |
|------------|-------:|-------:|
| Permanent synthetic publication tests | 23 | 0 |
| R7 direct verification checks | 15 | 0 |
| Hardened R8/R9 regression checks | 13 | 0 |
| Total | 51 | 0 |

The Phase C verification wrapper additionally
passed all 19 checks, including four R8/R9
summary checks.

The Phase B configuration regression remains
at 10 passed and zero failed.

### Conclusion and limitations

Atomic COM publication preserves the tested
WoFS v1.0 scientific baseline and prevents
invalid temporary products from replacing
the final COM product under the tested conditions.

Concurrent execution protection remains Phase D.

Uncatchable termination may leave temporary files.
Atomic rename does not guarantee storage durability
following a filesystem failure.

Source mode bits are preserved, but existing
destination ownership and ACLs are not explicitly
preserved.

The complete hardened workflow will be exercised
in the final 36-member ensemble regression.
