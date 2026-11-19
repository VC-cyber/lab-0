`timescale 1ns / 1ps

// SW[2:0]: select card slot (0-6)
// SW3: edit cards (two digits, then E; D deletes)
// SW15: set/show number of players (one digit 2-6, then E)
// btnL: one player folds
// btnC: new game: clear cards, restore original number of players
// btnR: full reset: clear cards, start with 2 players
module inputs #(
    parameter SCAN_CYCLES = 100000,
    parameter DEBOUNCE_FRAMES = 3,
    parameter BUTTON_DEBOUNCE_CYCLES = 2000000
)(
    input clk,
    input btnR, btnC, btnL,
    input [15:0] sw,
    output [3:0] col,
    input [3:0] row,
    output [5:0] hole1, hole2,
    output [5:0] board1, board2, board3, board4, board5,
    output reg [2:0] num_players,
    output [6:0] led,
    output reg [3:0] an,
    output reg [6:0] seg
);
    // Keypad reader: a one-clock key_pressed pulse on each keypress.
    wire [3:0] key;
    wire key_pressed;
    keypad_reader #(.SCAN_CYCLES(SCAN_CYCLES),
                    .DEBOUNCE_FRAMES(DEBOUNCE_FRAMES)) keypad (
        .clk(clk), .btnR(btnR | btnC),
        .col(col), .row(row), .key(key), .key_pressed(key_pressed)
    );

    // Seven cards. Zero means the slot is empty.
    reg [5:0] cards [0:6];
    assign hole1  = cards[0];
    assign hole2  = cards[1];
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

    // Debounce btnL so one press counts as exactly one fold.
    reg left_ff1, left_ff2, left_stable;
    reg [20:0] left_counter;
    wire left_pressed = left_ff2 && !left_stable &&
                        (left_counter == BUTTON_DEBOUNCE_CYCLES - 1);

    always @(posedge clk or posedge btnR) begin
        if (btnR) begin
            left_ff1 <= 0;
            left_ff2 <= 0;
            left_stable <= 0;
            left_counter <= 0;
        end else begin
            left_ff1 <= btnL;
            left_ff2 <= left_ff1;
            if (left_ff2 == left_stable)
                left_counter <= 0;
            else if (left_counter == BUTTON_DEBOUNCE_CYCLES - 1) begin
                left_stable <= left_ff2;
                left_counter <= 0;
            end else
                left_counter <= left_counter + 1;
        end
    end

    reg [2:0] original_players; // Saved starting player count
    wire [2:0] slot = sw[2:0];
    reg [2:0] old_slot;
    reg old_edit, old_player_mode;
    reg [1:0] digits;          // Number of card digits entered: 0, 1, or 2
    reg [3:0] tens, ones;
    reg player_pending;       // One player-count digit has been typed
    reg [3:0] player_digit;
    integer i;

    always @(posedge clk or posedge btnR) begin
        if (btnR) begin
            for (i = 0; i < 7; i = i + 1)
                cards[i] <= 0;
            num_players <= 2;
            original_players <= 2;
            old_slot <= 0;
            old_edit <= 0;
            old_player_mode <= 0;
            digits <= 0;
            tens <= 0;
            ones <= 0;
            player_pending <= 0;
            player_digit <= 0;
        end else if (btnC) begin
            // New game: remember original_players; undo every fold.
            for (i = 0; i < 7; i = i + 1)
                cards[i] <= 0;
            num_players <= original_players;
            old_slot <= slot;
            old_edit <= sw[3];
            old_player_mode <= sw[15];
            digits <= 0;
            player_pending <= 0;
        end else begin
            old_slot <= slot;
            old_edit <= sw[3];
            old_player_mode <= sw[15];

            if (left_pressed && num_players > 1)
                num_players <= num_players - 1;

            // Changing modes or selecting a new card cancels unfinished typing.
            if (sw[15] != old_player_mode ||
                (!sw[15] && (sw[3] != old_edit || slot != old_slot))) begin
                digits <= 0;
                player_pending <= 0;
            end else if (key_pressed) begin
                if (sw[15]) begin
                    // SW15 overrides SW3: one digit + E sets player count.
                    case (key)
                        2,3,4,5,6: begin
                            player_digit <= key;
                            player_pending <= 1;
                        end
                        14: begin       // E: save starting number of players
                            if (player_pending) begin
                                original_players <= player_digit[2:0];
                                num_players <= player_digit[2:0];
                            end
                            player_pending <= 0;
                        end
                        13: player_pending <= 0; // D: cancel typing
                        default: ;
                    endcase
                end else if (sw[3] && slot < 7) begin
                    // Existing two-digit card entry.
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
                        14: begin     // E: save selected card
                            if (digits == 2)
                                cards[slot] <= tens * 10 + ones;
                            digits <= 0;
                        end
                        13: begin     // D: delete selected card
                            cards[slot] <= 0;
                            digits <= 0;
                        end
                        default: ;
                    endcase
                end
            end
        end
    end

    // SW15: show active players, or a digit being entered.
    // SW3 (when SW15 is off): show the selected card / card-entry preview.
    reg [3:0] show_tens, show_ones;
    reg tens_on, ones_on;
    always @(*) begin
        show_tens = 0;
        show_ones = 0;
        tens_on = 0;
        ones_on = 0;
        if (sw[15]) begin
            show_ones = player_pending ? player_digit : {1'b0, num_players};
            ones_on = 1;
        end else if (sw[3] && slot < 7) begin
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

    // Display refresh: same style as the stopwatch project.
    reg [15:0] refresh_counter;
    reg [3:0] LED_BCD;
    always @(posedge clk or posedge btnR) begin
        if (btnR) refresh_counter <= 0;
        else refresh_counter <= refresh_counter + 1;
    end

    always @(*) begin
        an = 4'b1111;
        LED_BCD = 0;
        if (sw[15]) begin
            an = 4'b1110;              // Only rightmost digit for players
            LED_BCD = show_ones;
        end else if (sw[3]) begin
            if (!refresh_counter[15] && ones_on) begin
                an = 4'b1110;
                LED_BCD = show_ones;
            end else if (refresh_counter[15] && tens_on) begin
                an = 4'b1101;
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
        if (an == 4'b1111) seg = 7'b1111111;
    end
endmodule
