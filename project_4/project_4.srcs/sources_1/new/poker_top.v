`timescale 1ns / 1ps

// Top-level Basys 3 signals only. Card values and player count stay internal.
module poker_top (
    input wire clk,
    input wire btnR, btnC, btnL,
    input wire [15:0] sw,
    output wire [3:0] col,
    input wire [3:0] row,
    output wire [6:0] led,
    output wire [3:0] an,
    output wire [6:0] seg
);
    wire [5:0] hole1, hole2;
    wire [5:0] board1, board2, board3, board4, board5;
    wire [2:0] num_players;
    wire [3:0] input_an;
    wire [6:0] input_seg;

    inputs game_inputs (
        .clk(clk), .btnR(btnR), .btnC(btnC), .btnL(btnL),
        .sw(sw), .col(col), .row(row),
        .hole1(hole1), .hole2(hole2),
        .board1(board1), .board2(board2), .board3(board3),
        .board4(board4), .board5(board5),
        .num_players(num_players),
        .led(led), .an(input_an), .seg(input_seg)
    );

    // SW15: show player count. SW3: show/edit card. Both OFF: odds later.
    assign an = (sw[15] || sw[3]) ? input_an : 4'b1111;
    assign seg = (sw[15] || sw[3]) ? input_seg : 7'b1111111;
endmodule
