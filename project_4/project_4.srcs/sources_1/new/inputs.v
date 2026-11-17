`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/17/2026 12:13:00 PM
// Design Name: 
// Module Name: inputs
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
// Type 01..52 on Pmod KYPD, then E to save; D deletes the selected card.
// SW[2:0]: 0/1 = hole cards, 2..6 = community cards, 7 = unused.
// Cards: 1..13 spades, 14..26 hearts, 27..39 diamonds, 40..52 clubs.
module inputs #(
    parameter integer SCAN_CYCLES = 100_000, // 1 ms per column at 100 MHz
    parameter integer DEBOUNCE_FRAMES = 5
)(
    input wire clk, btnR,
    input wire [2:0] sw,
    inout wire [7:0] JA,
    output wire [5:0] hole1, hole2,
    output wire [5:0] board1, board2, board3, board4, board5,
    output wire [6:0] valid,
    output reg changed, error, digit_pending,
    output reg [3:0] pending_tens,
    output wire [5:0] selected_card
);
    reg [5:0] cards [0:6]; // 0 = empty, 1..52 = card ID
    assign hole1=cards[0], hole2=cards[1];
    assign board1=cards[2], board2=cards[3], board3=cards[4];
    assign board4=cards[5], board5=cards[6];
    assign valid = {cards[6]!=0, cards[5]!=0, cards[4]!=0,
                    cards[3]!=0, cards[2]!=0, cards[1]!=0, cards[0]!=0};

    reg [2:0] sw_sync, slot;
    always @(posedge clk) begin
        sw_sync <= sw;
        slot <= sw_sync;
    end
    assign selected_card = (slot < 7) ? cards[slot] : 6'd0;

    // Keypad: JA[3:0] = driven columns, JA[7:4] = input rows.
    reg [1:0] col;
    reg [16:0] scan_timer;
    assign JA[3:0] = ~(4'b1000 >> col);
    assign JA[7:4] = 4'bzzzz;
    wire [3:0] rows = {JA[4], JA[5], JA[6], JA[7]};
    reg [3:0] rows_meta, rows_sync;
    always @(posedge clk) begin
        rows_meta <= rows;
        rows_sync <= rows_meta;
    end

    // Key layout: 1 2 3 A / 4 5 6 B / 7 8 9 C / 0 F E D
    // 16 means no recognized key.
    function [4:0] decode;
        input [1:0] c;
        input [3:0] r;
        begin
            case ({c,r})
                6'b00_1110: decode=1;  6'b01_1110: decode=2;
                6'b10_1110: decode=3;  6'b11_1110: decode=10;
                6'b00_1101: decode=4;  6'b01_1101: decode=5;
                6'b10_1101: decode=6;  6'b11_1101: decode=11;
                6'b00_1011: decode=7;  6'b01_1011: decode=8;
                6'b10_1011: decode=9;  6'b11_1011: decode=12;
                6'b00_0111: decode=0;  6'b01_0111: decode=15;
                6'b10_0111: decode=14; 6'b11_0111: decode=13;
                default: decode=16;
            endcase
        end
    endfunction

    // Scan four columns and generate one pulse per physical keypress.
    wire [4:0] sample = decode(col, rows_sync);
    reg [4:0] scanned, candidate, stable;
    wire [4:0] frame_key = (sample != 16) ? sample : scanned;
    reg [3:0] frames;
    reg [3:0] key_code;
    reg key_pulse;
    always @(posedge clk or posedge btnR) begin
        if (btnR) begin
            col<=0; scan_timer<=0; scanned<=16;
            candidate<=16; stable<=16; frames<=0;
            key_code<=0; key_pulse<=0;
        end else begin
            key_pulse <= 0;
            if (scan_timer == SCAN_CYCLES-1) begin
                scan_timer <= 0;
                col <= col+1'b1;
                if (col != 3) begin
                    if (sample != 16) scanned <= sample;
                end else begin
                    scanned <= 16;
                    if (frame_key != candidate) begin
                        candidate <= frame_key;
                        frames <= 1;
                    end else if (frames < DEBOUNCE_FRAMES) begin
                        frames <= frames+1'b1;
                        if (frames == DEBOUNCE_FRAMES-1 && stable != frame_key) begin
                            stable <= frame_key;
                            if (frame_key != 16) begin
                                key_code <= frame_key[3:0];
                                key_pulse <= 1;
                            end
                        end
                    end
                end
            end else scan_timer <= scan_timer+1'b1;
        end
    end

    // Buffer at most two decimal digits. Only E commits the card.
    reg [1:0] digits; // 0, 1, or 2 digits buffered
    reg [3:0] ones;
    reg [2:0] previous_slot;
    wire [6:0] card_id = pending_tens * 7'd10 + ones;
    reg duplicate;
    integer j;
    always @* begin
        duplicate = 0;
        for (j=0; j<7; j=j+1)
            if (j != slot && card_id != 0 && cards[j] == card_id)
                duplicate = 1;
    end

    integer i;
    always @(posedge clk or posedge btnR) begin
        if (btnR) begin
            for (i=0; i<7; i=i+1) cards[i] <= 0;
            previous_slot<=0; digits<=0; ones<=0; pending_tens<=0;
            digit_pending<=0; changed<=0; error<=0;
        end else begin
            changed <= 0;
            if (slot != previous_slot) begin
                previous_slot <= slot;
                digits <= 0; digit_pending <= 0; error <= 0;
            end else if (key_pulse) begin
                case (key_code)
                    13: begin // D: delete selected card (and cancel entry)
                        digits<=0; digit_pending<=0; error<=0;
                        if (slot < 7 && cards[slot] != 0) begin
                            cards[slot] <= 0;
                            changed <= 1;
                        end
                    end
                    14: begin // E: save exactly two digits
                        digits<=0; digit_pending<=0;
                        if (slot == 7 || digits != 2 ||
                            card_id < 1 || card_id > 52 || duplicate)
                            error <= 1;
                        else begin
                            error <= 0;
                            if (cards[slot] != card_id) begin
                                cards[slot] <= card_id[5:0];
                                changed <= 1;
                            end
                        end
                    end
                    0,1,2,3,4,5,6,7,8,9: begin
                        if (slot == 7) error <= 1;
                        else if (digits == 0) begin
                            pending_tens<=key_code; digits<=1;
                            digit_pending<=1; error<=0;
                        end else if (digits == 1) begin
                            ones<=key_code; digits<=2;
                        end
                        // After two digits, ignore extras until E or D.
                    end
                    default: ; // A, B, C, F unused
                endcase
            end
        end
    end
endmodule

