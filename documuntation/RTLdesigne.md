8. RTL Design Overview

This section describes the Register Transfer Level (RTL) architecture of the proposed TPU-inspired AI accelerator. The RTL design follows a modular and hierarchical structure, enabling clarity, scalability, and ease of verification.

8.1 Top-Level Architecture

At the top level, the accelerator consists of the following major RTL modules:

+---------------------+
|  Command Interface  |
+----------+----------+
           |
+----------v----------+
|  Command Decoder    |
+----------+----------+
           |
+----------v----------+
|  Central Control    |
|  FSM / Scheduler   |
+----+-----+-----+----+
     |     |     |
     v     v     v
  Memory  Compute  Post-Processing
  Subsys  Subsys       Subsys
The top module integrates all submodules and connects to the host processor through a memory-mapped or AXI-based interface.
8.2 Command Interface Module
Function:
Receives commands from the host processor
Stores commands in a FIFO or register queue
Key RTL Components:
Command FIFO (for buffering commands)
Write interface (MMIO or AXI-Lite)
Read pointer for command consumption
Design Note:
Commands are fixed-width (e.g., 64-bit) and processed strictly in-order.
8.3 Command Decoder Module
Function:
Decodes the opcode and fields of each command
Generates control signals for downstream modules
Decoded Information:
Command opcode (CONFIG, LOAD, MATMUL, etc.)
Source and destination buffer addresses
Matrix size and precision
Operation-specific flags
RTL Characteristics:
Pure combinational logic
No data path computation
Low latency
8.4 Central Control FSM / Scheduler
Function:
Coordinates execution of command
Manages command lifecycle (start, busy, done)
Ensures correct sequencing and synchronization
Responsibilities:
Enable or disable submodules based on opcode
Track command completion
Enforce SYNC semantics
Design Style:
Finite State Machine (FSM)
Deterministic transitions
No speculative execution
8.5 Memory Subsystem
Function:
Store input activations, weights, and outputs
Provide high-bandwidth access to compute units
Components:
On-chip buffers (BRAM / URAM)
Address generation logic
Optional DMA controller (AXI-DMA)
Design Features:
Banked memory for parallel access
Double buffering (ping–pong buffers)
Separate read/write ports where possible
8.6 Compute Subsystem (Systolic Array)
Function:
Perform matrix multiply–accumulate operations
Components:
MAC processing elements (DSP-based)
Systolic interconnect (local neighbor connections
Accumulator registers (wider precision)
RTL Characteristics:
Fully pipelined
Fixed dataflow
Parameterizable array size (e.g., 8×8, 16×16)
8.7 Accumulator Module
Function
Store partial sum
Support accumulation across multiple MATMUL commands
Features:
Wider bit-width than input precision
Saturation and overflow control
Clear and hold modes (controlled by ACCUM command)
8.8 Activation & Reduction Subsystem
Function:
Apply non-linear operations and reductions
Supported Operations:
ReLU
Scaling and quantization
Sum / average / max reduction
RTL Style:
Pipelined combinational logic
LUT-based or arithmetic operators
Often placed after accumulator stage
8.9 Store & Writeback Module
Function:
Write results from on-chip buffers back to external memory
Components:
Write address generator
DMA or streaming interface
Completion signaling
Optimization:
Overlap STORE with LOAD or MATMUL when possible
8.10 Synchronization Logic
Function:
Ensure correct ordering between commands
Implement SYNC semantics
Implementation:
Status flags
Busy / done signals from submodules
Pipeline flush control
9. RTL Design Characteristics Summary
Modular and hierarchical design
Deterministic command execution
No branching or speculative logic
Optimized for FPGA resources
Easily extensible for future enhancements
10. Design Extensibility
The RTL architecture allows future extensions such as:
Command fusion (MATMUL + ACT)
Support for additional precisions
Larger systolic arrays
Overlapping compute and memory operations