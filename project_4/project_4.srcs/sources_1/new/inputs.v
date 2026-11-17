`timescale 1ns / 1ps
// Texas Hold'em card input for Basys 3 + Pmod KYPD.
// sw[2:0] selects slot 0..6. sw[3] enables editing.
// Enter two digits (01..52), then E to save. D deletes the selected card.
// A zero-valued card slot is empty. LEDs 0..6 show filled slots.
// In edit mode the seven-segment display shows the selected card / entry.
// When edit is OFF, this module blanks the display so the top-level
// probability display can take over later.
module inputs #(
    parameter integer SCAN_CYCLES = 100_000,  // 1 ms per column at 100 MHz
    parameter integer DEBOUNCE_FRAMES = 5     // 20 ms (4 columns/frame)
)(
    input  wire       clk,
    input  wire       btnR,
    input  wire [3:0] sw,     // sw[3] = edit, sw[2:0] = card slot
    inout  wire [7:0] JA,
    output wire [5:0] hole1, hole2,
    output wire [5:0] board1, board2, board3, board4, board5,
    output wire [6:0] led,
    output reg  [3:0] an,
    output reg  [6:0] seg
);
    // Seven card slots: 0=empty; 1..52=card ID.
    reg [5:0] cards [0:6];
    assign hole1  = cards[0];
    assign hole2  = cards[1];
    assign board1 = cards[2];
    assign board2 = cards[3];
    assign board3 = cards[4];
    assign board4 = cards[5];
    assign board5 = cards[6];

    genvar i;
    generate
        for (i = 0; i < 7; i = i + 1) begin : slot_leds
            assign led[i] = (cards[i] != 0);
        end
    endgenerate

    wire [2:0] slot = sw[2:0];
    wire edit_mode = sw[3];

    // --- Keypad scanner: active-low columns (JA[3:0]), rows (JA[7:4]). ---
    reg [1:0] col;
    reg [16:0] scan_timer;
    assign JA[3:0] = ~(4'b1000 >> col);
    assign JA[7:4] = 4'bzzzz;

    wire [3:0] rows = {JA[4], JA[5], JA[6], JA[7]};
    reg [3:0] row_sync1, row_sync2;
    always @(posedge clk) begin
        row_sync1 <= rows;
        row_sync2 <= row_sync1;
    end

    // Key layout: 1 2 3 A / 4 5 6 B / 7 8 9 C / 0 F E D
    // 16 means no key detected.
    function [4:0] decode;
        input [1:0] c;
        input [3:0] r;
        begin
            case ({c, r})
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

    // One key press produces one pulse (holding it won't repeat).
    wire [4:0] sample = decode(col, row_sync2);
    reg [4:0] scanned, candidate, stable;
    wire [4:0] frame_key = (sample != 16) ? sample : scanned;
    reg [3:0] frames;
    reg [3:0] key_code;
    reg key_pulse;

    always @(posedge clk or posedge btnR) begin
        if (btnR) begin
            col <= 0; scan_timer <= 0; scanned <= 16;
            candidate <= 16; stable <= 16; frames <= 0;
            key_code <= 0; key_pulse <= 0;
        end else begin
            key_pulse <= 0;
            if (scan_timer == SCAN_CYCLES-1) begin
                scan_timer <= 0;
                col <= col + 1'b1;
                if (col != 3) begin
                    if (sample != 16) scanned <= sample;
                end else begin
                    scanned <= 16;
                    if (frame_key != candidate) begin
                        candidate <= frame_key;
                        frames <= 1;
                    end else if (frames < DEBOUNCE_FRAMES) begin
                        frames <= frames + 1'b1;
                        if (frames == DEBOUNCE_FRAMES-1 && stable != frame_key) begin
                            stable <= frame_key;
                            if (frame_key != 16) begin
                                key_code <= frame_key[3:0];
                                key_pulse <= 1;
                            end
                        end
                    end
                end
            end else begin
                scan_timer <= scan_timer + 1'b1;
            end
        end
    end

    // --- Card entry: two digits, then E (save) or D (delete). ---
    reg [3:0] last_sw;
    reg [1:0] digits;
    reg [3:0] tens, ones;
    integer j;
    always @(posedge clk or posedge btnR) begin
        if (btnR) begin
            for (j = 0; j < 7; j = j + 1) cards[j] <= 0;
            last_sw <= 0;
            digits <= 0;
            tens <= 0;
            ones <= 0;
        end else begin
            last_sw <= sw;
            if (!edit_mode || sw != last_sw) begin
                digits <= 0;  // cancel entry when switching slots/modes
            end else if (key_pulse && slot < 7) begin
                if (key_code <= 9) begin
                    if (digits == 0) begin
                        tens <= key_code;
                        digits <= 1;
                    end else if (digits == 1) begin
                        ones <= key_code;
                        digits <= 2;
                    end
                    // Ignore any digits beyond the first two.
                end else if (key_code == 14) begin // E = save
                    if (digits == 2) cards[slot] <= tens * 10 + ones;
                    digits <= 0;
                end else if (key_code == 13) begin // D = delete
                    cards[slot] <= 0;
                    digits <= 0;
                end
            end
        end
    end

    // --- Card preview in edit mode. ---
    reg [3:0] show_tens, show_ones;
    reg tens_on, ones_on;
    always @* begin
        show_tens = 0; show_ones = 0;
        tens_on = 0; ones_on = 0;
        if (edit_mode) begin
            if (digits != 0) begin
                show_tens = tens;
                tens_on = 1;
                if (digits == 2) begin
                    show_ones = ones;
                    ones_on = 1;
                end
            end else if (slot < 7 && cards[slot] != 0) begin
                show_tens = cards[slot] / 10;
                show_ones = cards[slot] % 10;
                tens_on = 1;
                ones_on = 1;
            end
        end
    end

    // Active-low seven-segment decoder (a,b,c,d,e,f,g).
    function [6:0] seven_seg;
        input [3:0] digit;
        begin
            case (digit)
                0: seven_seg=7'b1000000; 1: seven_seg=7'b1111001;
                2: seven_seg=7'b0100100; 3: seven_seg=7'b0110000;
                4: seven_seg=7'b0011001; 5: seven_seg=7'b0010010;
                6: seven_seg=7'b0000010; 7: seven_seg=7'b1111000;
                8: seven_seg=7'b0000000; 9: seven_seg=7'b0010000;
                default: seven_seg=7'b1111111;
            endcase
        end
    endfunction

    // Refresh the rightmost two digits. Off in probability mode.
    reg [15:0] refresh;
    always @(posedge clk or posedge btnR)
        if (btnR) refresh <= 0;
        else refresh <= refresh + 1'b1;

    always @* begin
        an = 4'b1111;
        seg = 7'b1111111;
        if (edit_mode) begin
            if (refresh[15] == 0 && ones_on) begin
                an = 4'b1110;
                seg = seven_seg(show_ones);
            end else if (refresh[15] == 1 && tens_on) begin
                an = 4'b1101;
                seg = seven_seg(show_tens);
            end
        end
    end
endmodule
