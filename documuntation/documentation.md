Command Set Architecture for TPU-Inspired AI Accelerator
1. Introduction

This project adopts a command-based execution model, inspired by the Google Tensor Processing Unit (TPU), to control a custom AI accelerator implemented on FPGA. Instead of using fine-grained CPU-like instructions, the accelerator executes coarse-grained commands, each representing a high-level operation such as data movement, matrix computation, or activation.

This approach reduces control complexity, improves hardware efficiency, and enables deterministic execution of static machine learning workloads.

2. Design Philosophy
The command set is designed based on the following principles:
Minimalism – A small number of powerful commands
Determinism – Predictable, in-order execution
Hardware Efficiency – Long-running commands maximize datapath utilization
Software-Controlled Complexity – Scheduling handled by software/compiler

The accelerator supports exactly eight commands, which together are sufficient to execute most neural network layers.

3. Command Execution Model

Commands are issued by the host processor and placed into a command queue.
The accelerator fetches and executes commands sequentially.
Key characteristics:
No branching or dynamic scheduling in hardware
Each command configures specific hardware blocks
Commands may execute for thousands of clock cycles
Execution order is deterministic


4. Supported Commands
4.1 CONFIG Command
Purpose:
Configure the operating mode of the accelerator.
Functions:
Select computation precision (INT8 / FP16)
Configure tile size
Set accumulation and dataflow modes
This command is typically issued at the beginning of each layer

4.2 LOAD Command
Purpose:
Transfer data from external memory to on-chip buffers.
Functions:
Load input activations
Load weights and bias values
Initialize on-chip memory regions
This command activates the DMA engine.

4.3 MATMUL Command

Purpose:
Perform matrix multiplication on the systolic MAC array.
Operation:
C = A × B + C
Functions:
Enable MAC array
Execute multiply–accumulate operations
Generate partial or complete results
This is the core compute comman

4.4 ACCUM Command
Purpose:
Control accumulator behavior.
Functions:
Clear accumulator registers
Accumulate partial results
Apply saturation control
This command supports tiled matrix computation.
4.5 ACT Command
Purpose:
Apply activation and post-processing operations.
Supported operations:
ReLU
Scaling
Quantization and clamping
This command prepares results for storage or further computation.

4.6 REDUCE Command
Purpose:
Perform reduction operations.
Supported operations:
Sum
Average pooling
Max pooling
This command is commonly used in CNN and attention workloads.


4.7 STORE Command
Purpose:
Transfer data from on-chip buffers back to external memory
Functions:
Store output tensors
Store intermediate results
This command uses DMA for efficient memory transfer.

4.8 SYNC Command
Purpose:
Provide synchronization and execution ordering.
Functions:
Wait for completion of previous commands
Ensure memory and compute consistency
Flush internal pipelines
This command performs no computation.


 Conclusion
The proposed 8-command architecture provides a complete, minimal, and scalable control interface for an FPGA-based AI accelerator. By shifting scheduling complexity to software and keeping hardware execution deterministic, the design achieves high efficiency while remaining extensible for future enhancements such as command fusion and overlapped computation.

