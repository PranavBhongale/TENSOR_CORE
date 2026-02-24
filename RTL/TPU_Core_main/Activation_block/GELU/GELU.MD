we  want to integrate the GELU which is of LUT BASED   by using   LOOK TABLE 
Recommended:
Clip input to [-4, +4]            this is for LOOK UP TABLE 
Use 8-bit index
16-bit output                 

 I  Want Slightly Better Precision  
so i decided to  
Use:
10-bit index
16-bit output

total memory i need for it is 
2^10=1024
1024×16=16384 bits
       = 2 KB

     very reasonable  


why clamping 

Why Clamping Is Needed

    GELU (and similar activations) are meaningful only in limited range.
    Practically:
    x∈[−4,+4]
    Outside this:
    GELU(x > 4) ≈ x
    GELU(x < -4) ≈ 0






