`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/15/2026 12:40:22 PM
// Design Name: 
// Module Name: tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb;
reg [11:0] D_in;
wire [7:0] out;

FPCVT uut (.num12(D_in), .num8(out));

initial 
begin
    $display("--------------------------------------------------");
    
    D_in = 12'b011111111111; 
    #10;
    $display("%b\t", out);
 end  

endmodule
