`timescale 1ns / 1ps

// Physical Basys 3 pin interface. All card values remain INSIDE the FPGA.
module poker_top (
    input wire clk,
    input wire btnR, btnC, btnL,
    input wire [15:0] sw,
    output wire [3:0] col,
    input wire [3:0] row,
    output wire [6:0] led,
    output wire [3:0] an,
    output wire [6:0] seg,
    output wire dp
);
    wire [5:0] hole1, hole2;
    wire [5:0] board1, board2, board3, board4, board5;
    wire [2:0] num_players;
    wire [3:0] input_an;
    wire [6:0] input_seg;

    // This is your previously tested input module, unchanged.
    inputs game_inputs (
        .clk(clk), .btnR(btnR), .btnC(btnC), .btnL(btnL),
        .sw(sw), .col(col), .row(row),
        .hole1(hole1), .hole2(hole2),
        .board1(board1), .board2(board2), .board3(board3),
        .board4(board4), .board5(board5),
        .num_players(num_players),
        .led(led), .an(input_an), .seg(input_seg)
    );

    // Detect committed card changes and folds. This does not react to
    // half-typed numbers, only when the saved values actually change.
    wire [44:0] all_inputs = {num_players,
                               board5,board4,board3,board2,board1,
                               hole2,hole1};
    reg [44:0] previous_inputs;
    reg calculate;
    always @(posedge clk or posedge btnR or posedge btnC) begin
        if (btnR || btnC) begin
            previous_inputs <= 0;
            calculate <= 0;
        end else begin
            calculate <= 0;
            if (all_inputs != previous_inputs) begin
                previous_inputs <= all_inputs;
                calculate <= 1;
            end
        end
    end

    wire ready, busy;
    wire [9:0] win_tenths, equity_tenths;
    simulation_engine #(.NUM_SIMS(10000)) simulator (
        .clk(clk), .rst(btnR | btnC), .start(calculate),
        .hole1(hole1), .hole2(hole2),
        .board1(board1), .board2(board2), .board3(board3),
        .board4(board4), .board5(board5),
        .num_players(num_players),
        .ready(ready), .busy(busy),
        .win_tenths(win_tenths), .equity_tenths(equity_tenths)
    );

    wire [3:0] odds_an;
    wire [6:0] odds_seg;
    wire odds_dp;
    // SW14: optional equity instead of outright win probability.
    probability_display odds_display (
        .clk(clk), .ready(ready),
        .percent_tenths(sw[14] ? equity_tenths : win_tenths),
        .an(odds_an), .seg(odds_seg), .dp(odds_dp)
    );

    // SW15 -> player display, SW3 -> edit card display.
    // Both OFF -> live Monte Carlo winning percentage.
    assign an  = (sw[15] || sw[3]) ? input_an : odds_an;
    assign seg = (sw[15] || sw[3]) ? input_seg : odds_seg;
    assign dp  = (sw[15] || sw[3]) ? 1'b1 : odds_dp;
endmodule
