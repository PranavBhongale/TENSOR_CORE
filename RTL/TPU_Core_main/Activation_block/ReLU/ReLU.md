ReLU Integration in Systolic Array Accelerator

 Objective

Integrate ReLU activation after matrix computation:

Y=A×B+C

to form a complete neural network layer in hardware.
current data flow in the TPU_CORE 
Systolic Array (MAC units)
        ↓
Accumulator (12-cycle latency)
        ↓
ReLU (Combinational)
        ↓
Final Output

Matrix result available in parallel as:
psum_out [ROWS][COLS]
ReLU applied element-wise.
No extra pipeline stage (combinational).


3️⃣ ReLU Implementation Concept

For signed accumulator:

​3️⃣ ReLU Implementation Concept

For signed accumulator:


	
otherwise
ReLU(x)={ 0  if x<0
          x  otherwise 
	​
Hardware interpretation:
Check MSB (sign bit)
If MSB = 1 → output 0
Else → pass input

Synthesizes to:
1 multiplexer per element
No large comparator
No extra arithmetic

4️⃣ Timing Consideration
Since matrix output is already registered:
ReLU is combinational
No synchronization required
Total latency remains 12 cycles
Optional upgrade:
Add register after ReLU → latency becomes 13 cycles (pipeline clean stage separation)

