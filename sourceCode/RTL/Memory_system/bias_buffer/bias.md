byas type 
            00 → no bias
            01 → scalar bias
            10 → vector bias
            11 → matrix bias

this bias type we need for processing the bias value    if it is no bias  stream 00 into the mac 
of bias type is scalar type then feed the constant value to all the PE  
if the bias is vector then feed the vector coloum wise 
if full bias  feed full matrix striming 

 we are provind the bias value as serial data   input    and 
 then it will store into buffer   if the matrix is to larg 
 if it is not to larg   like 95%  of the work load is used the vector bias   so at  that time 
 we use   8byte full two buffer  
 then it is processed and then streamed into  the mac     