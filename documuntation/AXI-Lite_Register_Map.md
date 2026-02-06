Registers are the contract between software and hardware.
They let software configure, control, and observe hardware without knowing its internal RTL.
Without registers:
Software cannot control the accelerator
Hardware becomes unusable

AXI-Lite Register Map Table
| Offset (Hex) | Register Name | Width | Access | Description                  |
| ------------ | ------------- | ----- | ------ | ---------------------------- |
| `0x0000`     | CTRL          | 32    | R/W    | Global control register      |
| `0x0004`     | STATUS        | 32    | R      | Accelerator status           |
| `0x0008`     | CMD_LO        | 32    | W      | Command lower 32 bits        |
| `0x000C`     | CMD_HI        | 32    | W      | Command upper 32 bits        |
| `0x0010`     | CMD_PUSH      | 32    | W      | Push command into FIFO       |
| `0x0014`     | CMD_COUNT     | 32    | R      | Number of pending commands   |
| `0x0020`     | BUF_ID        | 32    | W      | Buffer ID selector           |
| `0x0024`     | BUF_ADDR_LO   | 32    | W      | Buffer DRAM address (low)    |
| `0x0028`     | BUF_ADDR_HI   | 32    | W      | Buffer DRAM address (high)   |
| `0x002C`     | BUF_SIZE      | 32    | W      | Buffer size in bytes         |
| `0x0030`     | IRQ_ENABLE    | 32    | R/W    | Interrupt enable             |
| `0x0034`     | IRQ_STATUS    | 32    | R/W    | Interrupt status / clear     |
| `0x0040`     | PERF_CYCLES   | 32    | R      | Performance counter (cycles) |
| `0x0044`     | PERF_CMDS     | 32    | R      | Executed command count       |


22.1 CTRL Register (0x0000)
| Bit  | Name     | Description             |
| ---- | -------- | ----------------------- |
| 0    | START    | Start command execution |
| 1    | RESET    | Reset accelerator       |
| 2    | FLUSH    | Flush command FIFO      |
| 31:3 | Reserved | —                       |


22.2 STATUS Register (0x0004)
| Bit  | Name     | Description      |
| ---- | -------- | ---------------- |
| 0    | BUSY     | Accelerator busy |
| 1    | IDLE     | Accelerator idle |
| 2    | ERROR    | Error detected   |
| 31:3 | Reserved | —                |

22.3 Command Registers (CMD_LO, CMD_HI, CMD_PUSH)
Commands are written as 64-bit values using two registers:
CMD_HI (31:0) → bits [63:32]
CMD_LO (31:0) → bits [31:0]
After writing both halves:
Writing 1 to CMD_PUSH enqueues the command into the command FIFO.
📌 This mechanism supports your fixed 64-bit command format.

22.4 CMD_COUNT Register (0x0014)
Indicates number of commands currently queued
Useful for debugging and flow control

22.5 Buffer Mapping Registers (0x0020 – 0x002C)
These registers define the Buffer ID → DRAM mapping.
Programming sequence:
Write buffer ID to BUF_ID
Write DRAM base address to BUF_ADDR_LO / BUF_ADDR_HI
Write buffer size to BUF_SIZE
📌 This mapping is later referenced by LOAD / STORE commads.


22.6 Interrupt Registers
IRQ_ENABLE (0x0030)
Bit 0: Enable completion interrupt
Bit 1: Enable error interrupt
IRQ_STATUS (0x0034)
Bit 0: Command completion
Bit 1: Error condition
Writing 1 clears the corresponding interrupt

22.7 Performance Counters
PERF_CYCLES: Counts accelerator clock cycles
PERF_CMDS: Counts executed commands
📌 Optional but very useful for evaluation and debugging.

