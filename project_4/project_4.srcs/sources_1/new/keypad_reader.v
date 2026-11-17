`timescale 1ns / 1ps

// Pmod KYPD driver for the Basys 3: 4 columns, 4 rows, active LOW.
// Reports one key_pressed pulse for each physical key press.
module keypad_reader #(
    parameter SCAN_CYCLES = 100000,  // 1 ms per column at 100 MHz
    parameter DEBOUNCE_FRAMES = 3    // ~12-16 ms debounce
)(
    input clk,
    input btnR,
    output [3:0] col,
    input [3:0] row,
    output reg [3:0] key,
    output reg key_pressed
);
    reg [16:0] scan_counter;
    reg [1:0] column;
    assign col = ~(4'b1000 >> column);

    // Synchronize the four keypad row signals.
    reg [3:0] row1, row2;
    always @(posedge clk) begin
        row1 <= {row[0], row[1], row[2], row[3]};
        row2 <= row1;
    end

    // Keypad layout: 1 2 3 A / 4 5 6 B / 7 8 9 C / 0 F E D
    // 16 means no key is currently detected.
    reg [4:0] detected;
    always @(*) begin
        detected = 16;
        case ({column, row2})
            6'b00_1110: detected = 1;
            6'b01_1110: detected = 2;
            6'b10_1110: detected = 3;
            6'b11_1110: detected = 10;
            6'b00_1101: detected = 4;
            6'b01_1101: detected = 5;
            6'b10_1101: detected = 6;
            6'b11_1101: detected = 11;
            6'b00_1011: detected = 7;
            6'b01_1011: detected = 8;
            6'b10_1011: detected = 9;
            6'b11_1011: detected = 12;
            6'b00_0111: detected = 0;
            6'b01_0111: detected = 15;
            6'b10_0111: detected = 14; // E
            6'b11_0111: detected = 13; // D
        endcase
    end

    reg [4:0] frame_key, last_key, stable_key;
    reg [3:0] frames;
    wire [4:0] completed_key = (detected != 16) ? detected : frame_key;

    always @(posedge clk or posedge btnR) begin
        if (btnR) begin
            scan_counter <= 0;
            column <= 0;
            frame_key <= 16;
            last_key <= 16;
            stable_key <= 16;
            frames <= 0;
            key <= 0;
            key_pressed <= 0;
        end else begin
            key_pressed <= 0;
            if (scan_counter == SCAN_CYCLES - 1) begin
                scan_counter <= 0;
                column <= column + 1;

                if (column != 3) begin
                    if (detected != 16)
                        frame_key <= detected;
                end else begin
                    frame_key <= 16;
                    if (completed_key != last_key) begin
                        last_key <= completed_key;
                        frames <= 0;
                    end else if (frames < DEBOUNCE_FRAMES) begin
                        frames <= frames + 1;
                        if (frames == DEBOUNCE_FRAMES - 1 && stable_key != completed_key) begin
                            stable_key <= completed_key;
                            if (completed_key != 16) begin
                                key <= completed_key[3:0];
                                key_pressed <= 1;
                            end
                        end
                    end
                end
            end else begin
                scan_counter <= scan_counter + 1;
            end
        end
    end
endmodule
