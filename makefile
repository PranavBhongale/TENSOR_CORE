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
	sourceCode/RTL/TPU_Core_main/MAC/mac_top.sv \
    sourceCode/RTL/TPU_Core_main/MAC/pe_top.sv \
	sourceCode/RTL/TPU_Core_main/MAC/systolic_array_top.sv \
	sourceCode/RTL/TPU_Core_main/MAC/shift_register.sv \
	sourceCode/testbench/systolic_array_testbench/tb_systolic_array_for_two_test.sv

mac:
	$(VERILATOR) $(VFLAGS) \
	--top-module $(MAC_TOP) \
	$(MAC_SRC)
	./obj_dir/V$(MAC_TOP)


# activation block 
ACT_TOP = activation_block_tb

ACT_SRC = \
	sourceCode/RTL/TPU_Core_main/Activation_block/activation_top.sv \
	sourceCode/RTL/TPU_Core_main/Activation_block/data_lane.sv \
	sourceCode/RTL/TPU_Core_main/Activation_block/GELU/shift_unit.sv \
	sourceCode/RTL/TPU_Core_main/Activation_block/GELU/gelu_lut.sv \
	sourceCode/RTL/TPU_Core_main/Activation_block/GELU/Look_Table.sv \
	sourceCode/RTL/TPU_Core_main/Activation_block/GELU/Clamp_unit.sv \
    sourceCode/testbench/Activation_test_bench/activation_block_tb.sv

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
	sourceCode/RTL/**/*.sv \
	sourceCode/testbench/tb_top.sv

full:
	$(VERILATOR) $(VFLAGS) \
	--top-module $(FULL_TOP) \
	$(FULL_SRC)
	./obj_dir/V$(FULL_TOP)

#  TPU_CORE_TOP
TPU_CORE_TOP = TPU_CORE_TB

TPU_CORE_SOURCE = \
    $(shell find sourceCode/RTL/TPU_core_main -name "*.sv") \
    sourceCode/testbench/TPU_core_main_testbench/TPU_CORE_TB.SV

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
	sourceCode/RTL/TPU_Core_main/Activation_block/data_lane.sv \
	sourceCode/testbench/Activation_test_bench/data_lane_tb.sv
	./obj_dir/Vdata_lane_tb


#-----------------------------------------------------
# this is for bias file 
#-----------------------------------------------------

bias:
	$(VERILATOR) $(VFLAGS) \
	-I./sourceCode/RTL/Memory_system/bias_buffer \
	--top-module bias_medium  \
	sourceCode/RTL/Memory_system/bias_buffer/bias_brodcast.sv \
	sourceCode/RTL/Memory_system/bias_buffer/bias_controller.sv \
	sourceCode/RTL/Memory_system/bias_buffer/bias_top.sv \
	sourceCode/testbench/memory_unit_tb/bias_tb/bias_medium.sv

	./obj_dir/Vbias_medium

weight:
	$(VERILATOR) $(VFLAGS) \
	-I./sourceCode/RTL/Memory_system/weight_buffer \
	--top-module weight_tb  \
	sourceCode/RTL/Memory_system/weight_buffer/weight_buffer.sv \
	sourceCode/RTL/Memory_system/weight_buffer/weight_control.sv \
	sourceCode/RTL/Memory_system/weight_buffer/weight_top.sv \
	sourceCode/testbench/memory_unit_tb/weight_tb/weight_tb.sv
	./obj_dir/Vweight_tb


activation2:
	$(VERILATOR) $(VFLAGS) \
	-I./sourceCode/RTL/Memory_system/activation_buffer \
	--top-module activation_tb  \
	sourceCode/RTL/Memory_system/activation_buffer/activation_buffer.sv \
	sourceCode/RTL/Memory_system/activation_buffer/activation_control.sv \
	sourceCode/RTL/Memory_system/activation_buffer/activation_top.sv \
	sourceCode/testbench/memory_unit_tb/activation_tb/activation_tb.sv
	./obj_dir/Vactivation_tb


output:
	$(VERILATOR) $(VFLAGS) \
	-I./sourceCode/RTL/Memory_system/output_buffer \
	--top-module output_buffer_tb  \
	sourceCode/RTL/Memory_system/output_buffer/output_buffer.sv \
	sourceCode/RTL/Memory_system/output_buffer/output_control.sv \
	sourceCode/RTL/Memory_system/output_buffer/output_top.sv \
	sourceCode/testbench/memory_unit_tb/output_buffer_tb/output_buffer_tb.sv
	./obj_dir/Voutput_buffer_tb
