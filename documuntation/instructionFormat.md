Command Instruction Format (Opcode Definition)

All commands use a fixed 64-bit instruction format.
A fixed-width format simplifies RTL decoding, improves timing, and matches TPU design philosophy.



11.1 Global Command Format (64-bit)
63                                                        0
+--------+---------+---------+---------+--------+------+------+
| Opcode | Src Addr| Wt Addr | Dst Addr| Size   | Prec | Flags |
+--------+---------+---------+---------+--------+------+------+
   4b        12b        12b        12b      8b      4b     12b



Field Description
| Field    | Bits | Description                     |
| -------- | ---- | ------------------------------- |
| Opcode   | 4    | Command type (0–7)              |
| Src Addr | 12   | Source buffer address           |
| Wt Addr  | 12   | Weight buffer address           |
| Dst Addr | 12   | Destination buffer address      |
| Size     | 8    | Matrix/tensor size or tile size |
| Prec     | 4    | Precision mode                  |
| Flags    | 12   | Command-specific control flags  |


11.2 Opcode Encoding
| Opcode (Hex) | Command |
| ------------ | ------- |
| `0x0`        | CONFIG  |
| `0x1`        | LOAD    |
| `0x2`        | MATMUL  |
| `0x3`        | ACCUM   |
| `0x4`        | ACT     |
| `0x5`        | REDUCE  |
| `0x6`        | STORE   |
| `0x7`        | SYNC    |

11.3 Precision Encoding (Prec Field)
| Prec Value | Meaning  |
| ---------- | -------- |
| `0x0`      | INT8     |
| `0x1`      | INT16    |
| `0x2`      | FP16     |
| `0x3`      | Reserved |





LOAD Command (Opcode = 0x1)
| Opcode | Src Addr | ---- | Dst Addr | Size | ---- | ---- |

| Field    | Meaning             |
| -------- | ------------------- |
| Src Addr | DRAM buffer ID      |
| Dst Addr | On-chip buffer ID   |
| Size     | Number of elements  |
| Wt Addr  | Ignored             |
| Prec     | Ignored             |
| Flags    | Optional (DMA mode) |

🔹 STORE Command (Opcode = 0x6)
| Opcode | Src Addr | ---- | Dst Addr | Size | ---- | ---- |
Same format, different meaning

🔹 SYNC Command (Opcode = 0x7)
Only opcode is used.
Everything else ignored.


All commands use a fixed 64-bit instruction format. 
The interpretation of individual fields depends on the opcode. 
For a given command, only the relevant fields are decoded and used by hardware, 
while unused fields are treated as don’t-care values and ignored. 
This design simplifies instruction decoding, enables a uniform command queue, 
and aligns with TPU-style command-based execution.


