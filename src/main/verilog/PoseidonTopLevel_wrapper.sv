module PoseidonTopLevel_wrapper #(
    parameter bit SEQUENTIAL = 1
)(
    input               io_input_valid,
    output              io_input_ready,
    input               io_input_last,
    
    input      [0:8][254:0] io_input_payload, 
    
    input      [6:0]        round_idx, 
    
    output              io_output_valid,
    input               io_output_ready,
    output              io_output_last,
    
    output     [0:8][254:0] io_output_payload, 
    
    input               clk,
    input               reset
);

    // IMPORTANTE: Importar o package com as novas constantes de Fault Detection
    import poseidon_fault_constants_pkg::*;

    // ==========================================
    // 0. FAULT DETECTION ENCODER (A * R mod P)
    // ==========================================
    logic               encoded_valid;
    logic               encoded_ready;
    logic [0:8][254:0]  encoded_payload;
    logic               encoded_last;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            encoded_last <= 1'b0;
        end else if (io_input_valid && io_input_ready) begin
            encoded_last <= io_input_last;
        end
    end

    fault_encoder_in encoder_inst (
        .clk(clk),
        .reset(reset),
        
        .io_input_valid(io_input_valid),
        .io_input_ready(io_input_ready),
        .io_input_payload(io_input_payload),
        
        .io_output_valid(encoded_valid),
        .io_output_ready(encoded_ready),
        .io_output_payload(encoded_payload)
    );

    // ==========================================
    // SINAIS INTERMÉDIOS (POSEIDON -> DECODER)
    // ==========================================
    logic               poseidon_valid;
    logic               poseidon_ready;
    logic [0:8][254:0]  poseidon_payload;
    logic               poseidon_last;

    // ==========================================
    // POSEIDON HASH IMPLEMENTATION
    // ==========================================
    if (SEQUENTIAL) begin: SEQUENTIAL_IMPLEMENTATION 

        typedef enum logic [3:0] {
            IDLE, FEED_SBOX, WAIT_SBOX, BYPASS_SBOX, 
            START_MATRIX, WAIT_MATRIX, DONE_STATE
        } state_e;
        
        state_e current_state, next_state;

        logic [6:0] internal_round_idx; 
        logic [3:0] sbox_idx; 
        logic [0:8][254:0] latched_input;
        logic [0:8][254:0] sbox_outputs;
        logic last_reg;

        logic is_partial_round;
        assign is_partial_round = (internal_round_idx >= 7'd4) && (internal_round_idx <= 7'd60);

        logic sbox_in_valid, sbox_in_ready;
        logic [254:0] sbox_in_payload;
        
        logic sbox_out_valid, sbox_out_ready;
        logic [254:0] sbox_out_payload;

        logic matrix_start, matrix_ready, matrix_done;
        logic [0:8][254:0] matrix_state_out;

        logic [9:0]   seq_const_idx;
        logic [254:0] seq_selected_constant, seq_adder_out;

        assign seq_const_idx = (internal_round_idx * 9) + sbox_idx;
        assign seq_selected_constant = FAULT_ROUND_CONSTANTS[seq_const_idx];

        ModAdder #() add_round_const_seq (
            .op1_i(latched_input[sbox_idx]),
            .op2_i(seq_selected_constant),
            .res_o(seq_adder_out)
        );

        assign sbox_in_payload = seq_adder_out;

        sbox sbox_inst (
            .io_input_valid(sbox_in_valid),
            .io_input_ready(sbox_in_ready),
            .io_input_last(1'b0), 
            .io_input_payload(sbox_in_payload),
            .io_output_valid(sbox_out_valid),
            .io_output_ready(sbox_out_ready),
            .io_output_payload(sbox_out_payload),
            .clk(clk), .reset(reset)
        );

        // NOVA LIGAÇÃO: Passar o is_partial_round para a mix_layer
        mix_layer_sequential #(.N(9)) mix_layer_inst (
            .clk(clk), .reset(reset),
            .start(matrix_start),
            .is_partial_round_i(is_partial_round), // <--- AQUI
            .state_in(sbox_outputs), 
            .ready(matrix_ready),
            .done(matrix_done),
            .state_out(matrix_state_out)
        );

        always_ff @(posedge clk or posedge reset) begin
            if (reset) begin
                current_state <= IDLE;
                sbox_idx <= '0;
                latched_input <= '0;
                sbox_outputs <= '0;
                last_reg <= 1'b0;
                internal_round_idx <= '0;
            end else begin
                current_state <= next_state;

                case (current_state)
                    IDLE: begin
                        if (encoded_valid) begin
                            latched_input <= encoded_payload;
                            last_reg <= encoded_last;
                            sbox_idx <= '0;
                            internal_round_idx <= '0;
                        end
                    end
                    WAIT_SBOX: begin
                        if (sbox_out_valid && sbox_out_ready) begin
                            sbox_outputs[sbox_idx] <= sbox_out_payload;
                            if (sbox_idx < 4'd8) sbox_idx <= sbox_idx + 1'b1;
                        end
                    end
                    BYPASS_SBOX: begin
                        sbox_outputs[sbox_idx] <= seq_adder_out;
                        if (sbox_idx < 4'd8) sbox_idx <= sbox_idx + 1'b1;
                    end
                    WAIT_MATRIX: begin
                        if (matrix_done) begin
                            latched_input <= matrix_state_out; 
                            if (internal_round_idx < 7'd64) begin
                                internal_round_idx <= internal_round_idx + 1'b1;
                                sbox_idx <= '0;
                            end
                        end
                    end
                    default: ; 
                endcase
            end
        end

        logic io_input_ready_logic;
        logic io_output_valid_logic;

        always_comb begin
            next_state = current_state;
            io_input_ready_logic = 1'b0;
            io_output_valid_logic = 1'b0;
            sbox_in_valid = 1'b0;
            sbox_out_ready = 1'b0;
            matrix_start = 1'b0;

            case (current_state)
                IDLE: begin
                    io_input_ready_logic = 1'b1;
                    if (encoded_valid) next_state = FEED_SBOX;
                end
                FEED_SBOX: begin
                    sbox_in_valid = 1'b1;
                    if (sbox_in_ready) next_state = WAIT_SBOX;
                end
                WAIT_SBOX: begin
                    sbox_out_ready = 1'b1;
                    if (sbox_out_valid) begin
                        if (sbox_idx == 4'd8) next_state = START_MATRIX;
                        else if (is_partial_round) next_state = BYPASS_SBOX;
                        else next_state = FEED_SBOX;
                    end
                end
                BYPASS_SBOX: begin
                    if (sbox_idx == 4'd8) next_state = START_MATRIX;
                    else next_state = BYPASS_SBOX;
                end
                START_MATRIX: begin
                    matrix_start = 1'b1;
                    if (matrix_ready) next_state = WAIT_MATRIX;
                end
                WAIT_MATRIX: begin
                    if (matrix_done) begin
                        if (internal_round_idx == 7'd64) next_state = DONE_STATE;
                        else next_state = FEED_SBOX;
                    end
                end
                DONE_STATE: begin
                    io_output_valid_logic = 1'b1;
                    if (poseidon_ready) next_state = IDLE;
                end
                default: next_state = IDLE;
            endcase
        end

        assign encoded_ready = io_input_ready_logic;
        
        assign poseidon_valid = io_output_valid_logic;
        assign poseidon_payload = latched_input; 
        assign poseidon_last = last_reg;

    end else begin: PARALLEL_IMPLEMENTATION

        logic [0:8] io_input_valid_sboxes;
        logic [0:8] io_input_ready_sboxes;
        logic [0:8] io_input_last_sboxes;
        logic [0:8][254:0] io_input_payload_sboxes;
        
        logic [0:8] io_output_valid_sboxes;
        logic [0:8] io_output_ready_sboxes;
        logic [0:8][254:0] io_output_payload_sboxes;
        
        logic [0:8][9:0]   par_const_idx;
        logic [0:8][254:0] par_adder_out;

        // NOVO: Definir is_partial_round para a versão paralela
        logic is_partial_round;
        assign is_partial_round = (round_idx >= 7'd4) && (round_idx <= 7'd60);
        
        for (genvar j = 0; j < 9; j++) begin : gen_inputs
            assign io_input_valid_sboxes[j]   = encoded_valid;
            assign io_input_last_sboxes[j]    = encoded_last;
            assign io_input_payload_sboxes[j] = encoded_payload[j];
        end

        assign encoded_ready = &io_input_ready_sboxes;

        for (genvar i = 0; i < 9; i++) begin : gen_sboxes
            assign par_const_idx[i] = (round_idx * 9) + i;
            
            ModAdder #() add_round_const_par (
                .op1_i(io_input_payload_sboxes[i]),
                .op2_i(FAULT_ROUND_CONSTANTS[par_const_idx[i]]),
                .res_o(par_adder_out[i])
            );

            sbox sbox_inst (
                .io_input_valid(io_input_valid_sboxes[i]),
                .io_input_ready(io_input_ready_sboxes[i]),
                .io_input_last(io_input_last_sboxes[i]),
                .io_input_payload(par_adder_out[i]),
                .io_output_valid(io_output_valid_sboxes[i]),
                .io_output_ready(io_output_ready_sboxes[i]),
                .io_output_payload(io_output_payload_sboxes[i]),
                .clk(clk), .reset(reset)
            );
        end
        
        logic matrix_start, matrix_ready, matrix_done;
        logic [0:8][254:0] matrix_state_out;

        wire all_sboxes_valid = &io_output_valid_sboxes;
        assign matrix_start = all_sboxes_valid & matrix_ready;

        for (genvar k = 0; k < 9; k++) begin : gen_sbox_ready
            assign io_output_ready_sboxes[k] = matrix_start;
        end

        logic [0:8][254:0] latched_sbox_payload;

        always_ff @(posedge clk or posedge reset) begin
            if (reset) latched_sbox_payload <= '0;
            else if (matrix_start) latched_sbox_payload <= io_output_payload_sboxes;
        end

        // NOVA LIGAÇÃO: Passar o is_partial_round para a mix_layer (versão paralela)
        mix_layer_sequential #(.N(9)) mix_layer_inst (
            .clk(clk), .reset(reset),
            .start(matrix_start),
            .is_partial_round_i(is_partial_round), // <--- AQUI
            .state_in(latched_sbox_payload), 
            .ready(matrix_ready),
            .done(matrix_done),
            .state_out(matrix_state_out)
        );

        assign poseidon_valid   = matrix_done;
        assign poseidon_payload = matrix_state_out;

        reg last_reg;
        assign poseidon_last = last_reg;
        always_ff @(posedge clk) begin
            if (encoded_valid && encoded_ready) last_reg <= encoded_last;
        end

    end

    // ==========================================
    // FINAL. FAULT DETECTION DECODER (A^-1 * R mod P)
    // ==========================================
    logic decoded_last;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            decoded_last <= 1'b0;
        end else if (poseidon_valid && poseidon_ready) begin
            decoded_last <= poseidon_last;
        end
    end

    fault_decoder_out decoder_inst (
        .clk(clk),
        .reset(reset),
        
        .io_input_valid(poseidon_valid),
        .io_input_ready(poseidon_ready),
        .io_input_payload(poseidon_payload),
        
        .io_output_valid(io_output_valid),
        .io_output_ready(io_output_ready),
        .io_output_payload(io_output_payload)
    );

    assign io_output_last = decoded_last;

endmodule