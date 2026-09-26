/*
 * main.c
 *
 *  Created on: Dec 6, 2019
 *      Author: J. Vrachnis
 */

#include <stdio.h>
#include "xil_io.h"
int main (void)
{
printf("Test Project\n\r");
printf("Writing to a custom IP register...");
Xil_Out32(0x43C00000, 0xA83);
Xil_Out32(0x43C00004, 0x0);
Xil_Out32(0x43C00008, 0xDEADBEEF);
Xil_Out32(0x43C0000C, 0x1);
printf("Done\n\r");
return 0;
}
