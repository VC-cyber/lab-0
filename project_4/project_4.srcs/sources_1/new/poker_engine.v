`timescale 1ns / 1ps
// ============================================================================
// POKER ENGINE - ALL ODDS CALCULATION MODULES IN ONE FILE
// Add this ONE file as a Design Source in Vivado.
// Contains 3 modules: hand_evaluator, simulation_engine, probability_display.
// Required memory files: noflush7.mem, flush7.mem, hash_offsets.mem
// ============================================================================

// =====================================================================
// HAND EVALUATOR: base-5 rank counts, perfect hash and ROMs
// =====================================================================
// Exact seven-card evaluator. One evaluation takes ~37 clocks at 100 MHz.
// Card codes: 1=A spades, 2=2 spades, ... 13=K spades;
//             14=A hearts ... 26=K hearts; ... 52=K clubs.
// strength: 1 = strongest possible, 7462 = weakest.
//
// The rank counters are exactly the 13 base-5 digits of the rank key:
// base5_key = sum(rank_count[r] * 5^(12-r)), r=0(A) .. 12(2).
// A small table compresses those base-5 digits into a 0..49204 ROM address.
module hand_evaluator (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [41:0] cards,       // {card6,card5,...,card0}, each 6 bits
    output reg done,
    output reg [12:0] strength,
    output reg [30:0] base5_key   // debugging/educational: base-5 encoding
);
    reg [2:0] rank_count [0:12]; // Ace, K, Q, ... 2
    reg [2:0] suit_count [0:3];
    reg [12:0] suit_mask [0:3]; // mask bit 12 = A, bit 0 = 2

    reg [2:0] card_index;
    reg [3:0] rank_index;
    reg [3:0] remaining;
    reg [15:0] hash;
    reg [3:0] state;
    reg [12:0] flush_mask;
    integer j;

    localparam IDLE        = 0;
    localparam BUILD       = 1;
    localparam CHECK_FLUSH = 2;
    localparam HASH_READ   = 3;
    localparam HASH_ADD    = 4;
    localparam ROM_READ    = 5;
    localparam ROM_RESULT  = 6;

    // Three initialized, read-only FPGA memories.
    (* rom_style = "block" *) reg [15:0] hash_offsets [0:519];
    (* rom_style = "block" *) reg [12:0] noflush_rom [0:49204];
    (* rom_style = "block" *) reg [12:0] flush_rom   [0:8191];
    initial begin
        $readmemh("hash_offsets.mem", hash_offsets);
        $readmemh("noflush7.mem", noflush_rom);
        $readmemh("flush7.mem", flush_rom);
    end

    // Select one of the seven cards.
    reg [5:0] current_card;
    always @(*) begin
        case (card_index)
            0: current_card = cards[5:0];
            1: current_card = cards[11:6];
            2: current_card = cards[17:12];
            3: current_card = cards[23:18];
            4: current_card = cards[29:24];
            5: current_card = cards[35:30];
            6: current_card = cards[41:36];
            default: current_card = 0;
        endcase
    end

    // Convert 1..52 to one suit and rank in 1..13 (A=1, K=13).
    // These are constants and subtractors; no division or modulus hardware.
    reg [1:0] suit;
    reg [3:0] rank_in_suit;
    reg [3:0] rank_order;
    reg [3:0] rank_bit;
    always @(*) begin
        if (current_card <= 13) begin
            suit = 0;
            rank_in_suit = current_card[3:0];
        end else if (current_card <= 26) begin
            suit = 1;
            rank_in_suit = current_card - 13;
        end else if (current_card <= 39) begin
            suit = 2;
            rank_in_suit = current_card - 26;
        end else begin
            suit = 3;
            rank_in_suit = current_card - 39;
        end
        if (rank_in_suit == 1) begin
            rank_order = 0;
            rank_bit = 12;
        end else begin
            rank_order = 14 - rank_in_suit;
            rank_bit = rank_in_suit - 2;
        end
    end

    reg [30:0] rank_weight;
    always @(*) begin
        case (rank_in_suit)
            1:  rank_weight = 31'd244140625; // A = 5^12
            2:  rank_weight = 31'd1;
            3:  rank_weight = 31'd5;
            4:  rank_weight = 31'd25;
            5:  rank_weight = 31'd125;
            6:  rank_weight = 31'd625;
            7:  rank_weight = 31'd3125;
            8:  rank_weight = 31'd15625;
            9:  rank_weight = 31'd78125;
            10: rank_weight = 31'd390625;
            11: rank_weight = 31'd1953125;
            12: rank_weight = 31'd9765625;
            13: rank_weight = 31'd48828125;
            default: rank_weight = 0;
        endcase
    end

    // At each rank, the offset counts all lexicographically smaller
    // 7-card rank-count patterns with the same prefix.
    wire [9:0] offset_address = rank_index * 10'd40 +
                                remaining * 10'd5 + rank_count[rank_index];
    reg [15:0] offset_value;
    reg [12:0] nonflush_value, flush_value;
    always @(posedge clk) begin
        offset_value <= hash_offsets[offset_address];
        nonflush_value <= noflush_rom[hash];
        flush_value <= flush_rom[flush_mask];
    end

    reg flush_found;
    reg [12:0] selected_mask;
    always @(*) begin
        flush_found = 0;
        selected_mask = 0;
        if (suit_count[0] >= 5) begin
            flush_found = 1; selected_mask = suit_mask[0];
        end else if (suit_count[1] >= 5) begin
            flush_found = 1; selected_mask = suit_mask[1];
        end else if (suit_count[2] >= 5) begin
            flush_found = 1; selected_mask = suit_mask[2];
        end else if (suit_count[3] >= 5) begin
            flush_found = 1; selected_mask = suit_mask[3];
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            done <= 0;
            strength <= 0;
            base5_key <= 0;
            card_index <= 0;
            rank_index <= 0;
            remaining <= 0;
            hash <= 0;
            flush_mask <= 0;
            state <= IDLE;
            for (j=0; j<13; j=j+1) rank_count[j] <= 0;
            for (j=0; j<4; j=j+1) begin
                suit_count[j] <= 0;
                suit_mask[j] <= 0;
            end
        end else begin
            done <= 0;
            case (state)
                IDLE: begin
                    if (start) begin
                        for (j=0; j<13; j=j+1) rank_count[j] <= 0;
                        for (j=0; j<4; j=j+1) begin
                            suit_count[j] <= 0;
                            suit_mask[j] <= 0;
                        end
                        base5_key <= 0;
                        card_index <= 0;
                        state <= BUILD;
                    end
                end
                BUILD: begin
                    rank_count[rank_order] <= rank_count[rank_order] + 1'b1;
                    suit_count[suit] <= suit_count[suit] + 1'b1;
                    suit_mask[suit] <= suit_mask[suit] | (13'b1 << rank_bit);
                    base5_key <= base5_key + rank_weight;
                    if (card_index == 6)
                        state <= CHECK_FLUSH;
                    else
                        card_index <= card_index + 1'b1;
                end
                CHECK_FLUSH: begin
                    if (flush_found) begin
                        flush_mask <= selected_mask;
                        state <= ROM_READ;
                    end else begin
                        rank_index <= 0;
                        remaining <= 7;
                        hash <= 0;
                        state <= HASH_READ;
                    end
                end
                HASH_READ: state <= HASH_ADD;
                HASH_ADD: begin
                    hash <= hash + offset_value;
                    remaining <= remaining - rank_count[rank_index];
                    if (rank_index == 12)
                        state <= ROM_READ;
                    else begin
                        rank_index <= rank_index + 1'b1;
                        state <= HASH_READ;
                    end
                end
                ROM_READ: state <= ROM_RESULT;
                ROM_RESULT: begin
                    strength <= flush_found ? flush_value : nonflush_value;
                    done <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

// =====================================================================
// MONTE CARLO ENGINE: randomized deals and 2–6 player comparison
// =====================================================================
// Monte Carlo Texas Hold'em odds engine, 2..6 players including hero.
// Draws random unknown cards without replacement and uses ONE evaluator.
// NUM_SIMS=10000 gives at most ~+/- 1 percentage point sampling uncertainty
// (95% confidence, assuming independent nearly-uniform simulations).
module simulation_engine #(
    parameter NUM_SIMS = 10000
)(
    input wire clk,
    input wire rst,
    input wire start, // one-clock pulse when known cards or players change
    input wire [5:0] hole1, hole2,
    input wire [5:0] board1, board2, board3, board4, board5,
    input wire [2:0] num_players,
    output reg ready,
    output reg busy,
    output reg [9:0] win_tenths,    // 0..1000 represents 0.0..100.0%
    output reg [9:0] equity_tenths  // ties share pot, also 0..1000
);
    // Number of active opponents: num_players - 1 (at most 5).
    // Max draw slots: 5 community + 10 opponent cards = 15.
    reg [5:0] sim_board [0:4];
    reg [5:0] opp_cards [0:9];
    reg [51:0] used_cards;
    reg [3:0] draw_index;
    reg [2:0] player_index;
    reg [13:0] simulations_done;
    reg [13:0] wins;
    reg [19:0] equity_points;
    reg [12:0] best_score;
    reg [2:0] best_count;
    reg hero_is_best;
    reg [3:0] state;

    localparam IDLE       = 0;
    localparam INIT_DEAL  = 1;
    localparam DEAL       = 2;
    localparam EVAL_START = 3;
    localparam EVAL_WAIT  = 4;
    localparam ADD_RESULT = 5;
    localparam NEXT_GAME  = 6;
    localparam FINISH     = 7;
    localparam DIV_WIN    = 8;
    localparam DIV_EQUITY = 9;
    reg [31:0] win_dividend;
    reg [31:0] equity_dividend;

    // Used-card bitmap of all known cards, including hero's two cards.
    reg [51:0] known_mask;
    always @(*) begin
        known_mask = 0;
        if (hole1  != 0) known_mask[hole1 - 1]  = 1'b1;
        if (hole2  != 0) known_mask[hole2 - 1]  = 1'b1;
        if (board1 != 0) known_mask[board1 - 1] = 1'b1;
        if (board2 != 0) known_mask[board2 - 1] = 1'b1;
        if (board3 != 0) known_mask[board3 - 1] = 1'b1;
        if (board4 != 0) known_mask[board4 - 1] = 1'b1;
        if (board5 != 0) known_mask[board5 - 1] = 1'b1;
    end

    // Known community-card slot selected by draw_index.
    reg [5:0] known_board_card;
    always @(*) begin
        case (draw_index)
            0: known_board_card = board1;
            1: known_board_card = board2;
            2: known_board_card = board3;
            3: known_board_card = board4;
            4: known_board_card = board5;
            default: known_board_card = 0;
        endcase
    end

    // Xorshift32 generator. Rejection sampling makes accepted 0..51
    // card IDs approximately uniform; the used-card mask avoids duplicates.
    reg [31:0] rng, free_counter;
    wire [31:0] x1 = rng ^ (rng << 13);
    wire [31:0] x2 = x1 ^ (x1 >> 17);
    wire [31:0] x3 = x2 ^ (x2 << 5);
    wire [5:0] candidate = rng[5:0];
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            free_counter <= 32'h12345678;
            rng <= 32'h9E3779B9;
        end else begin
            free_counter <= free_counter + 1'b1;
            if (start)
                rng <= (free_counter ^ 32'h9E3779B9) | 32'h00000001;
            else
                rng <= x3;
        end
    end

    // Exactly one shared hand evaluator.
    reg eval_start;
    reg [41:0] eval_cards;
    wire eval_done;
    wire [12:0] eval_score;
    wire [30:0] base5_key;
    hand_evaluator evaluator (
        .clk(clk), .rst(rst | start),
        .start(eval_start), .cards(eval_cards),
        .done(eval_done), .strength(eval_score), .base5_key(base5_key)
    );

    // Select the two cards belonging to the player being evaluated.
    // player_index=0 is our hero; 1..5 are random opponents.
    reg [5:0] player_card1, player_card2;
    always @(*) begin
        if (player_index == 0) begin
            player_card1 = hole1;
            player_card2 = hole2;
        end else begin
            player_card1 = opp_cards[(player_index-1)*2];
            player_card2 = opp_cards[(player_index-1)*2+1];
        end
    end

    // 60 is divisible by 1,2,3,4,5,6 -> integer tie accounting.
    reg [6:0] pot_points;
    always @(*) begin
        pot_points = 0;
        if (hero_is_best) begin
            case (best_count)
                1: pot_points = 60;
                2: pot_points = 30;
                3: pot_points = 20;
                4: pot_points = 15;
                5: pot_points = 12;
                6: pot_points = 10;
                default: pot_points = 0;
            endcase
        end
    end

    integer k;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            ready <= 0;
            busy <= 0;
            win_tenths <= 0;
            equity_tenths <= 0;
            used_cards <= 0;
            draw_index <= 0;
            player_index <= 0;
            simulations_done <= 0;
            wins <= 0;
            equity_points <= 0;
            best_score <= 0;
            best_count <= 0;
            hero_is_best <= 0;
            eval_start <= 0;
            eval_cards <= 0;
            win_dividend <= 0;
            equity_dividend <= 0;
            for (k=0;k<5;k=k+1) sim_board[k] <= 0;
            for (k=0;k<10;k=k+1) opp_cards[k] <= 0;
        end else if (start) begin
            // Restart immediately after any saved-card or player-count change.
            ready <= 0;
            busy <= 0;
            eval_start <= 0;
            simulations_done <= 0;
            wins <= 0;
            equity_points <= 0;
            if (hole1 == 0 || hole2 == 0 || num_players == 0) begin
                state <= IDLE; // Need both private cards before simulating.
            end else if (num_players == 1) begin
                // Everyone else has folded: automatically 100% winner.
                win_tenths <= 1000;
                equity_tenths <= 1000;
                ready <= 1;
                state <= IDLE;
            end else begin
                busy <= 1;
                state <= INIT_DEAL;
            end
        end else begin
            eval_start <= 0;
            case (state)
                IDLE: ;
                INIT_DEAL: begin
                    used_cards <= known_mask;
                    sim_board[0] <= board1;
                    sim_board[1] <= board2;
                    sim_board[2] <= board3;
                    sim_board[3] <= board4;
                    sim_board[4] <= board5;
                    draw_index <= 0;
                    state <= DEAL;
                end
                DEAL: begin
                    if (draw_index == (5 + 2*(num_players-1))) begin
                        // Board and opponents are complete.
                        player_index <= 0;
                        best_score <= 13'h1FFF;
                        best_count <= 0;
                        hero_is_best <= 0;
                        state <= EVAL_START;
                    end else if (draw_index < 5 && known_board_card != 0) begin
                        // This revealed community card is already present.
                        draw_index <= draw_index + 1'b1;
                    end else if (candidate < 52 && !used_cards[candidate]) begin
                        used_cards[candidate] <= 1'b1;
                        if (draw_index < 5)
                            sim_board[draw_index] <= candidate + 1'b1;
                        else
                            opp_cards[draw_index - 5] <= candidate + 1'b1;
                        draw_index <= draw_index + 1'b1;
                    end
                end
                EVAL_START: begin
                    eval_cards <= {
                        sim_board[4], sim_board[3], sim_board[2],
                        sim_board[1], sim_board[0], player_card2, player_card1
                    };
                    eval_start <= 1;
                    state <= EVAL_WAIT;
                end
                EVAL_WAIT: begin
                    if (eval_done) begin
                        if (eval_score < best_score) begin
                            best_score <= eval_score;
                            best_count <= 1;
                            hero_is_best <= (player_index == 0);
                        end else if (eval_score == best_score) begin
                            best_count <= best_count + 1'b1;
                        end
                        if (player_index == num_players - 1)
                            state <= ADD_RESULT;
                        else begin
                            player_index <= player_index + 1'b1;
                            state <= EVAL_START;
                        end
                    end
                end
                ADD_RESULT: begin
                    if (hero_is_best && best_count == 1)
                        wins <= wins + 1'b1;
                    equity_points <= equity_points + pot_points;
                    simulations_done <= simulations_done + 1'b1;
                    if (simulations_done == NUM_SIMS - 1)
                        state <= FINISH;
                    else
                        state <= INIT_DEAL;
                end
                FINISH: begin
                    // Fixed-point percent in tenths, rounded to nearest.
                    // Instead of a big combinational divider, use a simple
                    // repeated subtraction divider over ~0..1000 cycles.
                    win_dividend <= wins * 1000 + NUM_SIMS/2;
                    equity_dividend <= equity_points * 1000 + 30*NUM_SIMS;
                    win_tenths <= 0;
                    equity_tenths <= 0;
                    state <= DIV_WIN;
                end
                DIV_WIN: begin
                    if (win_dividend >= NUM_SIMS && win_tenths < 1000) begin
                        win_dividend <= win_dividend - NUM_SIMS;
                        win_tenths <= win_tenths + 1'b1;
                    end else
                        state <= DIV_EQUITY;
                end
                DIV_EQUITY: begin
                    if (equity_dividend >= 60*NUM_SIMS && equity_tenths < 1000) begin
                        equity_dividend <= equity_dividend - 60*NUM_SIMS;
                        equity_tenths <= equity_tenths + 1'b1;
                    end else begin
                        busy <= 0;
                        ready <= 1;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

// =====================================================================
// PERCENTAGE DISPLAY: multiplexed 7-segment output
// =====================================================================
// Four-digit seven-segment display: 42.5 means 42.5%.
// Decimal point is active LOW (Basys 3 DP pin V7).
module probability_display (
    input wire clk,
    input wire ready,
    input wire [9:0] percent_tenths, // 0..1000
    output reg [3:0] an,
    output reg [6:0] seg,
    output reg dp
);
    reg [15:0] refresh_counter = 0;
    reg [3:0] LED_BCD;
    always @(posedge clk)
        refresh_counter <= refresh_counter + 1'b1;

    always @(*) begin
        an = 4'b1111;
        dp = 1'b1;
        LED_BCD = 0;
        if (ready) begin
            case (refresh_counter[15:14])
                2'b00: begin
                    an = 4'b1110;
                    LED_BCD = percent_tenths % 10;
                end
                2'b01: begin
                    an = 4'b1101;
                    LED_BCD = (percent_tenths / 10) % 10;
                    dp = 1'b0; // Dot after the whole-percent digits.
                end
                2'b10: begin
                    if (percent_tenths >= 100) begin
                        an = 4'b1011;
                        LED_BCD = (percent_tenths / 100) % 10;
                    end
                end
                2'b11: begin
                    if (percent_tenths >= 1000) begin
                        an = 4'b0111;
                        LED_BCD = 1;
                    end
                end
            endcase
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

