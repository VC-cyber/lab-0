`timescale 1ns / 1ps
// Board-level top. Only real Basys 3 pins belong in this port list.
// The seven 6-bit card values stay INTERNAL for the later odds calculator.
module poker_top (
    input  wire       clk,
    input  wire       btnR,
    input  wire [3:0] sw,
    output wire [3:0] col,
    input  wire [3:0] row,
    output wire [6:0] led,
    output wire [3:0] an,
    output wire [6:0] seg
);
    wire [5:0] hole1, hole2;
    wire [5:0] board1, board2, board3, board4, board5;
    wire [3:0] card_an;
    wire [6:0] card_seg;

    inputs card_inputs (
        .clk(clk), .btnR(btnR), .sw(sw),
        .col(col), .row(row),
        .hole1(hole1), .hole2(hole2),
        .board1(board1), .board2(board2), .board3(board3),
        .board4(board4), .board5(board5),
        .led(led), .an(card_an), .seg(card_seg)
    );

    // Later: replace these blank constants with your odds-display signals.
    // SW3=1: card editing; SW3=0: probability display.
    assign an  = sw[3] ? card_an  : 4'b1111;
    assign seg = sw[3] ? card_seg : 7'b1111111;
endmodule
