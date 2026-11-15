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

## Phase D: Dual-resource locking

### Objective

Prevent concurrent IC_PREP executions from modifying the same
working directory or publishing to the same final COM destination.

### Implementation

- Acquire an exclusive, nonblocking working-directory lock.
- Acquire an exclusive, nonblocking COM destination lock.
- Acquire both locks before destructive working-directory cleanup.
- Return exit status 75 when a resource is already locked.
- Release the working-directory lock if COM lock acquisition fails.
- Retain both locks throughout scientific processing and publication.
- Release acquired locks when the execution process exits.
- Preserve persistent lock files to maintain stable inode identity.
- Canonicalize directory paths and reject unsafe lock-file types.

Implementation files:

- `scripts/exwofs_ic_prep.sh`
- `ush/lock_ic_prep.sh`
- `tests/check_ic_prep_locking.sh`

### Cross-node filesystem validation

Slurm job 26494390 verified advisory flock behavior on the shared
Ursa Lustre filesystem using two independent compute nodes.

Result: 6 PASS, 0 FAIL.

### Permanent regression tests

| Test suite | PASS | FAIL |
|---|---:|---:|
| IC_PREP inventory configuration | 10 | 0 |
| Atomic COM publication | 23 | 0 |
| Dual-resource locking | 23 | 0 |
| Total | 56 | 0 |

### Actual IC_PREP workflow regression

Case: HRRRDAS initialization 2026110214, valid 2026110215,
ensemble member 26.

Slurm job: 26495879.

Allocation: one node, 160 MPI tasks, 300 GB memory.

Job state: COMPLETED, exit status 0:0.

Elapsed time: 00:02:19.

UPP elapsed time: 00:01:04.

| Experiment | Expected exit | Actual exit | PASS | FAIL |
|---|---:|---:|---:|---:|
| R10: Working-directory conflict | 75 | 75 | 4 | 0 |
| R11: COM destination conflict | 75 | 75 | 5 | 0 |
| R12: Successful locked execution | 0 | 0 | 15 | 0 |
| Total | | | 24 | 0 |

R10 preserved the existing working file and produced no final
COM product.

R11 preserved both the existing working file and the existing
COM product. The working lock was released after the COM conflict.

R12 acquired both locks, completed UPP processing, passed all
GRIB2 inventory checks, published the final COM product atomically,
and released both locks. Persistent lock files remained intact.

### Scientific reproducibility

The R12 final native GRIB2 product contained 1167 records and
was bitwise identical to the original legacy UPP R1 reference.

SHA256:

    99d8b707d3e8c7839a9507bada5c2a2d8d82692741156f5b6de213ffeeca3799

The scientifically validated legacy UPP executable was unchanged.

### Portable Python runtime

The successful regression used the existing portable WoFS Python
environment with user-site packages disabled.

Validated dependencies:

- Python 3.11.12
- PyYAML 6.0.2
- NumPy 2.2.5
- netCDF4 1.7.4
- SciPy 1.15.2
- cftime 1.6.5

Python NetCDF library: 4.9.3.

Python HDF5 library: 1.14.6.

The dependency consistency check reported no broken requirements.

Two preliminary regression attempts, jobs 26495521 and 26495624,
failed before locking validation because the isolated NOAA Python
environment did not provide netCDF4. The successful experiment
resolved this issue using the portable Python interpreter.

The portable interpreter was configured only in the isolated
regression environment. Permanent shared IC_PREP and BC_PREP
Python runtime integration remains separate follow-up work.

### Scope and limitations

The locking mechanism is advisory and protects cooperating
workflow processes. Persistent lock files must not be removed
while executions may be active.

The actual workflow conflict experiments used independently
held filesystem locks rather than duplicate full UPP executions.

The successful scientific regression covers member 26.
A final full 36-member ensemble regression is planned before
merging the output-reliability branch into develop.

## R13: Final 36-member ensemble regression

### Configuration

- Initialization: 2026110214.
- Valid time: 2026110215.
- Workflow revision: e08e88a.
- Ensemble members: 36.
- MPI tasks per member: 160.
- Memory per member: 300 GB.
- Requested maximum concurrency: 36.
- IC_PREP job: 26496516.
- Validation job: 26497602.
- UPP: validated rebuilt legacy baseline.
- Python: portable WoFS Python 3.11.
- Scientific reference: R1 original legacy UPP.
- All four output-reliability phases enabled.

### Execution performance

| Metric | Result |
|---|---:|
| Completed members | 36 |
| Distinct compute nodes | 36 |
| Maximum simultaneous allocations | 36 |
| Minimum runtime (seconds) | 119 |
| Maximum runtime (seconds) | 131 |
| Mean runtime (seconds) | 121.44 |

### Independent validation

| Validation category | PASS | FAIL |
|---|---:|---:|
| Slurm completion | 36 | 0 |
| Raw WRFNAT (1000 records) | 36 | 0 |
| Raw WRFTWO (169 records) | 36 | 0 |
| Processed WRFTWO (167 records) | 36 | 0 |
| Final working WRFNAT (1167 records) | 36 | 0 |
| Final COM WRFNAT (1167 records) | 36 | 0 |
| Bitwise identity with R1 | 36 | 0 |
| Working-to-COM bitwise identity | 36 | 0 |
| Persistent working lock files | 36 | 0 |
| Persistent COM lock files | 36 | 0 |
| Working lock release | 36 | 0 |
| COM lock release | 36 | 0 |
| No temporary COM products | 36 | 0 |
| Total | 468 | 0 |

### Conclusions

All 36 final native GRIB2 products were bitwise
identical to the original legacy UPP reference.

All 180 independent inventory checks passed.

All 36 COM products were bitwise identical to
their corresponding working products.

All 72 persistent lock files were retained.
All 72 locks were successfully reacquired.

No temporary COM publication products remained.

The four output-reliability phases successfully
supported full 36-member ensemble concurrency.

### Scope and limitations

These results establish reproducibility for the
tested initialization and runtime configuration.

Concurrency measures overlapping Slurm allocations,
not simultaneous MPI execution.

Inventory counts cannot detect every possible
same-count corruption or missing mandatory field.

The portable Python interpreter was supplied
explicitly. Permanent runtime integration remains
separate follow-up work.

The initial validation job 26497035 failed due
to JobIDRaw accounting parsing. The corrected
validation used JobID and array-member filtering.
No scientific products were regenerated.

### Acceptance

All 468 validation checks passed with zero failures.
The implementation is accepted for integration
into develop.

### Validation provenance

- Experiment directory: /scratch3/NCEPDEV/stmp/Jianping.Huang/ic_prep_regression/R13_final_ensemble_20261115_035753
- Validation report: /scratch3/NCEPDEV/stmp/Jianping.Huang/ic_prep_regression/R13_final_ensemble_20261115_035753/validation_26497602
- Detailed results: results.tsv
- Accounting: accounting.tsv
- Concurrency: concurrency.txt
- Workflow checksums: workflow_files.sha256

## Phase E: Shared Python runtime regression

### Configuration

- Validation date: 2026-11-15.
- Platform: NOAA Ursa.
- Branch: feature/portable-python-runtime.
- Workflow revision: a0e2149719549b156c74264b2d94af77c1cc756e.
- Python: 3.11.12.
- Python environment: wofs_py311_p2_20261115_042228.
- Test filesystem: shared Ursa Lustre filesystem.

### Permanent regression results

| Test suite | PASS | FAIL |
|---|---:|---:|
| Inventory configuration | 10 | 0 |
| Atomic COM publication | 23 | 0 |
| Dual-resource locking | 23 | 0 |
| Total | 56 | 0 |

All shared Python runtime validation checks passed,
including package versions, installation locations,
dependency consistency, native libraries, and ecCodes
definitions.

### Reliability implementation

The existing locking and atomic publication helpers
remain unchanged relative to the develop baseline.

The existing COM overwrite policy is preserved:
successful reruns may atomically replace existing
products, while failed publication attempts preserve
existing valid products under the tested conditions.

### Acceptance

All 56 permanent reliability checks passed using the
new shared WoFS Python runtime.

No additional changes to the IC_PREP locking or
atomic publication implementation are required.

The previous R13 ensemble regression established
bitwise reproducibility for all 36 members using the
earlier portable Python environment.

A full ensemble regression using the newly integrated
shared Python runtime remains a separate integration
validation task.

### Validation provenance

- Regression directory: /scratch3/NCEPDEV/stmp/Jianping.Huang/WoFS_P6_reliability_20261115_180913.SR3JvhYh
- Summary: summary.txt
- Inventory tests: inventory.log
- Publication tests: publication.log
- Locking tests: locking.log
- Runtime modules: modules.log
- Python interpreter: python_path.txt
- Git revision: git_revision.txt
