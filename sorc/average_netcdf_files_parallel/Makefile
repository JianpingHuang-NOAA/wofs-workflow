#=======================================================================
# WoFS BC_PREP - Parallel NetCDF Ensemble Mean Utility
#
# Usage:
#   make clean   Remove generated build files
#   make         Compile and install executable into ../../exec/
#   make check   Verify runtime dependencies
#
# Requirements:
#   Intel MPI Fortran compiler
#   NetCDF-C, NetCDF-Fortran, Parallel-NetCDF
#=======================================================================

SHELL := /bin/bash

FC = mpiifort

TARGET := average_netcdf_files_parallel.x
SOURCE := average_netcdf_files_parallel.f90

BUILD_DIR := build
BUILD_TARGET := $(BUILD_DIR)/$(TARGET)

# NCO-style repository executable directory
EXEC_DIR ?= ../../exec
EXEC_TARGET := $(EXEC_DIR)/$(TARGET)

# Library configuration from loaded modules
NETCDF_C_PREFIX := $(shell nc-config --prefix)
PNETCDF_PREFIX := $(shell pnetcdf-config --prefix)

NETCDF_FFLAGS := $(shell nf-config --fflags)
NETCDF_FLIBS := $(shell nf-config --flibs)

FFLAGS ?= -O2

CPPFLAGS += $(NETCDF_FFLAGS)
CPPFLAGS += -I$(PNETCDF_PREFIX)/include

LDFLAGS += -L$(NETCDF_C_PREFIX)/lib
LDFLAGS += -L$(PNETCDF_PREFIX)/lib

LDLIBS += $(NETCDF_FLIBS) -lpnetcdf

.PHONY: all clean check install

# Default: build and install
all: install

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_TARGET): $(SOURCE) Makefile | $(BUILD_DIR)
	$(FC) $(FFLAGS) $(CPPFLAGS) \
	    $(SOURCE) \
	    $(LDFLAGS) $(LDLIBS) \
	    -o $(BUILD_TARGET)

check: $(BUILD_TARGET)
	@echo "===== Checking runtime dependencies ====="
	@ldd -r $(BUILD_TARGET) > $(BUILD_DIR)/ldd_check.log 2>&1 || { \
	    cat $(BUILD_DIR)/ldd_check.log; exit 1; \
	}
	@if grep -E 'undefined symbol|not found' $(BUILD_DIR)/ldd_check.log; then \
	    echo "[FAIL] Unresolved runtime dependencies"; \
	    exit 1; \
	else \
	    echo "[PASS] All runtime dependencies resolved"; \
	fi

install: check
	@echo "===== Installing executable ====="
	mkdir -p $(EXEC_DIR)
	install -m 755 $(BUILD_TARGET) $(EXEC_TARGET)
	@echo "[SUCCESS] Installed $(EXEC_TARGET)"

clean:
	@echo "===== Cleaning build files ====="
	rm -rf $(BUILD_DIR)
	rm -f *.o *.mod
	@echo "[SUCCESS] Clean completed"
