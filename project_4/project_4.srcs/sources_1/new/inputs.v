`timescale 1ns / 1ps

// Card entry for the Basys 3 Texas Hold'em calculator.
// SW[2:0] selects one of seven cards; SW3 turns editing ON.
// Type two digits (e.g. 06), then E to save. D deletes.
// Card IDs: 1-13 spades, 14-26 hearts, 27-39 diamonds, 40-52 clubs.
module inputs #(
    parameter SCAN_CYCLES = 100000,
    parameter DEBOUNCE_FRAMES = 3
)(
    input clk,
    input btnR,
    input [3:0] sw,
    output [3:0] col,
    input [3:0] row,
    output [5:0] hole1, hole2,
    output [5:0] board1, board2, board3, board4, board5,
    output [6:0] led,
    output reg [3:0] an,
    output reg [6:0] seg
);

    // Get a single key press from the physical Pmod keypad.
    wire [3:0] key;
    wire key_pressed;
    keypad_reader #(.SCAN_CYCLES(SCAN_CYCLES),
                    .DEBOUNCE_FRAMES(DEBOUNCE_FRAMES)) keypad (
        .clk(clk), .btnR(btnR), .col(col), .row(row),
        .key(key), .key_pressed(key_pressed)
    );

    // The seven saved cards. Zero means the position is empty.
    reg [5:0] cards [0:6];
    assign hole1 = cards[0];
    assign hole2 = cards[1];
    assign board1 = cards[2];
    assign board2 = cards[3];
    assign board3 = cards[4];
    assign board4 = cards[5];
    assign board5 = cards[6];

    assign led[0] = (cards[0] != 0);
    assign led[1] = (cards[1] != 0);
    assign led[2] = (cards[2] != 0);
    assign led[3] = (cards[3] != 0);
    assign led[4] = (cards[4] != 0);
    assign led[5] = (cards[5] != 0);
    assign led[6] = (cards[6] != 0);

    wire [2:0] slot = sw[2:0];
    reg [2:0] old_slot;
    reg [1:0] digits;          // 0, 1, or 2 digits entered
    reg [3:0] tens, ones;
    integer i;

    always @(posedge clk or posedge btnR) begin
        if (btnR) begin
            for (i = 0; i < 7; i = i + 1)
                cards[i] <= 0;
            old_slot <= 0;
            digits <= 0;
            tens <= 0;
            ones <= 0;
        end else begin
            old_slot <= slot;
            if (!sw[3] || slot != old_slot)
                digits <= 0;     // Stop editing when mode/slot changes
            else if (key_pressed && slot < 7) begin
                case (key)
                    0,1,2,3,4,5,6,7,8,9: begin
                        if (digits == 0) begin
                            tens <= key;
                            digits <= 1;
                        end else if (digits == 1) begin
                            ones <= key;
                            digits <= 2;
                        end
                    end
                    14: begin             // E: save the two digits
                        if (digits == 2)
                            cards[slot] <= tens * 10 + ones;
                        digits <= 0;
                    end
                    13: begin             // D: delete this card
                        cards[slot] <= 0;
                        digits <= 0;
                    end
                    default: ;
                endcase
            end
        end
    end

    // Show typed digits, or the saved card in the selected slot.
    reg [3:0] show_tens, show_ones;
    reg tens_on, ones_on;
    always @(*) begin
        show_tens = 0;
        show_ones = 0;
        tens_on = 0;
        ones_on = 0;
        if (sw[3] && slot < 7) begin
            if (digits > 0) begin
                show_tens = tens;
                tens_on = 1;
                if (digits == 2) begin
                    show_ones = ones;
                    ones_on = 1;
                end
            end else if (cards[slot] != 0) begin
                show_tens = cards[slot] / 10;
                show_ones = cards[slot] % 10;
                tens_on = 1;
                ones_on = 1;
            end
        end
    end

    // Same seven-segment refresh and BCD decoding style as stopwatch.v.
    reg [15:0] refresh_counter;
    reg [3:0] LED_BCD;
    always @(posedge clk or posedge btnR) begin
        if (btnR) refresh_counter <= 0;
        else refresh_counter <= refresh_counter + 1;
    end

    always @(*) begin
        an = 4'b1111;
        LED_BCD = 0;
        if (sw[3]) begin
            if (refresh_counter[15] == 0 && ones_on) begin
                an = 4'b1110;             // Rightmost digit
                LED_BCD = show_ones;
            end else if (refresh_counter[15] == 1 && tens_on) begin
                an = 4'b1101;             // Second digit from right
                LED_BCD = show_tens;
            end
        end
    end

    always @(*) begin
        case (LED_BCD)
            0: seg = 7'b1000000;
            1: seg = 7'b1111001;
            2: seg = 7'b0100100;
            3: seg = 7'b0110000;
            4: seg = 7'b0011001;
            5: seg = 7'b0010010;
            6: seg = 7'b0000010;
            7: seg = 7'b1111000;
            8: seg = 7'b0000000;
            9: seg = 7'b0010000;
            default: seg = 7'b1111111;
        endcase
        if (an == 4'b1111) seg = 7'b1111111; // Blank when not editing
    end
endmodule
