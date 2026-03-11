import numpy as np
from scipy.special import erf

# Integer byte domain
x_int = np.arange(-128, 128)

# Convert to real domain
# If SHIFT_BITS = 3, hardware scaled by 8
# so real value = x_int / (2^SHIFT_BITS)
SHIFT_BITS = 3
x_real = x_int / (2 ** SHIFT_BITS)

# GELU in real domain
gelu_real = x_real * 0.5 * (1 + erf(x_real / np.sqrt(2)))

# Convert back to integer domain
gelu_int = np.round(gelu_real * (2 ** SHIFT_BITS))

# Clamp to int8
gelu_int = np.clip(gelu_int, -128, 127).astype(np.int8)

# Save LUT
with open("gelu_lut.mem", "w") as f:
    for val in gelu_int:
        f.write(f"{int(val) & 0xFF:02x}\n")

print("Correct LUT Generated")

