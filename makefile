#====================================================
# Verilator Makefile for PE simulation (FIXED)
#====================================================

VERILATOR = verilator
TOP       = tb_systolic_array_for_two_test

# Source files with CORRECT paths
SRC = \
	RTL/MAC/mac_top.sv \
	RTL/MAC/pe_top.sv \
	RTL/MAC/systolic_array_top.sv \
	RTL/MAC/shift_register.sv \
	testbench/tb_systolic_array_for_two_test.sv \


# ---------------------------------------------------
# Default target
# ---------------------------------------------------
all: run

# ---------------------------------------------------
# Compile with Verilator
# ---------------------------------------------------
compile:
	$(VERILATOR) \
		--binary \
		--sv \
		--timing \
		--trace \
		-Wall \
		--top-module $(TOP) \
		$(SRC)

# ---------------------------------------------------
# Run simulation
# ---------------------------------------------------
run: compile
	./obj_dir/V$(TOP)

# ---------------------------------------------------
# Clean
# ---------------------------------------------------
clean:
	rm -rf obj_dir *.vcd
