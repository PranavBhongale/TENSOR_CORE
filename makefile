#====================================================
# Verilator Makefile for TPU Project
#====================================================

VERILATOR = verilator

#----------------------------------------------------
# Common Flags
#----------------------------------------------------
VFLAGS = \
	--binary \
	--sv \
	--timing \
	--trace \
	--trace-depth 10 \
	--build -j 8 \
	-Wall

#----------------------------------------------------
# MAC Block
#----------------------------------------------------
MAC_TOP = tb_systolic_array_for_two_test

MAC_SRC = \
	RTL/TPU_Core_main/MAC/mac_top.sv \
    RTL/TPU_Core_main/MAC/pe_top.sv \
	RTL/TPU_Core_main/MAC/systolic_array_top.sv \
	RTL/TPU_Core_main/MAC/shift_register.sv \
	testbench/systolic_array_testbench/tb_systolic_array_for_two_test.sv

mac:
	$(VERILATOR) $(VFLAGS) \
	--top-module $(MAC_TOP) \
	$(MAC_SRC)
	./obj_dir/V$(MAC_TOP)


# activation block 
ACT_TOP = activation_block_tb

ACT_SRC = \
	RTL/TPU_Core_main/Activation_block/activation_top.sv \
	RTL/TPU_Core_main/Activation_block/data_lane.sv \
	RTL/TPU_Core_main/Activation_block/GELU/shift_unit.sv \
	RTL/TPU_Core_main/Activation_block/GELU/gelu_lut.sv \
	RTL/TPU_Core_main/Activation_block/GELU/Look_Table.sv \
	RTL/TPU_Core_main/Activation_block/GELU/Clamp_unit.sv \
    testbench/Activation_test_bench/activation_block_tb.sv

activation:
	$(VERILATOR) $(VFLAGS) \
	--top-module $(ACT_TOP) \
	$(ACT_SRC)
	./obj_dir/V$(ACT_TOP)

#----------------------------------------------------
# Full TPU
#----------------------------------------------------
FULL_TOP = tb_top

FULL_SRC = \
	RTL/**/*.sv \
	testbench/tb_top.sv

full:
	$(VERILATOR) $(VFLAGS) \
	--top-module $(FULL_TOP) \
	$(FULL_SRC)
	./obj_dir/V$(FULL_TOP)

#  TPU_CORE_TOP
TPU_CORE_TOP = TPU_CORE_TB

TPU_CORE_SOURCE = \
    $(shell find RTL/TPU_core_main -name "*.sv") \
    testbench/TPU_core_main_testbench/TPU_CORE_TB.SV

tpu_core:
	$(VERILATOR) $(VFLAGS) \
		--cc \
		--exe \
		--build \
		--top-module $(TPU_CORE_TOP) \
		$(TPU_CORE_SOURCE)

	./obj_dir/V$(TPU_CORE_TOP)
#----------------------------------------------------
# Default
#----------------------------------------------------
all: mac

#----------------------------------------------------
# Clean
#----------------------------------------------------
clean:
	rm -rf obj_dir *.vcd

# --------------------------------------------------
#  this is for data lane testbench
# --------------------------------------------------	

data_lane:
	$(VERILATOR) $(VFLAGS) \
	--top-module data_lane_tb \
	RTL/TPU_Core_main/Activation_block/data_lane.sv \
	testbench/Activation_test_bench/data_lane_tb.sv
	./obj_dir/Vdata_lane_tb
