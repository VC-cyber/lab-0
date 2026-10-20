`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/15/2026 12:41:46 PM
// Design Name: 
// Module Name: FPCVT
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


module FPCVT( 
    input  [11:0] num12, // Fixed: Moved bit-width before variable name
    output reg [7:0] num8     // Fixed: Added reg so it can be assigned in always block
); 

reg [3:0] numE = 0; 
reg [2:0] e = 0; 
reg s; 
reg [3:0] f;
reg [11:0] temp_num12 = 0;  

task sBit; 
    begin 
        if(temp_num12[11] == 1)
            begin
                s = 1;
                temp_num12 = ~temp_num12;
                if(temp_num12 != 12'b011111111111)
                    begin
                        temp_num12 = temp_num12+1; 
                    end
            end 
    end 
endtask 

task eBits; 
    integer i;
    begin
        for (i = 0; i < 12; i = i + 1) begin
            if (temp_num12[11] == 0 && numE < 8) begin 
                numE = numE + 1; 
                temp_num12 = temp_num12 << 1;
            end 
        end
        e = 8-numE; 
    end 
endtask

task sigBits;
    reg r;
    begin
        f = temp_num12[11:8];
        r = temp_num12[7];
        
        if(r == 1'b1)
            begin
                f = f+1;
                if(f == 4'b0000)
                    begin
                        f = 4'b1000;
                        e = e+1;
                        if(e == 3'b000)
                            begin
                                e = 3'b111;
                                f = 4'b1111;
                            end
                    end
            end
        
    end
endtask

always @ (*)
    begin
        temp_num12 = num12;
        numE = 0;
        s = 0;
        
        sBit();
        eBits();
        sigBits();
        num8 = {s,e,f};
    end

endmodule
