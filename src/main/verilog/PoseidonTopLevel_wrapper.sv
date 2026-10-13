`include "poseidon_constants_t9.sv" 

module PoseidonTopLevel_wrapper #(
    parameter bit SEQUENTIAL = 1
)(
    input               io_input_valid,
    output              io_input_ready,
    input               io_input_last,
    
    input      [0:8][254:0] io_input_payload, 
    
    // Mantido para compatibilidade com a versão paralela
    input      [6:0]        round_idx, 
    
    output              io_output_valid,
    input               io_output_ready,
    output              io_output_last,
    
    output     [0:8][254:0] io_output_payload, 
    
    input               clk,
    input               reset
);

    if (SEQUENTIAL) begin: SEQUENTIAL_IMPLEMENTATION 

        // --- FSM States ---
        typedef enum logic [3:0] {
            IDLE,
            FEED_SBOX,
            WAIT_SBOX,
            BYPASS_SBOX,
            START_MATRIX,
            WAIT_MATRIX,
            DONE_STATE
        } state_e;
        
        state_e current_state, next_state;

        // --- Registers & Buffers ---
        logic [6:0] internal_round_idx;
        logic [3:0] sbox_idx;
        logic [0:8][254:0] latched_input;
        logic [0:8][254:0] sbox_outputs;
        logic last_reg;

        logic is_partial_round;
        assign is_partial_round = (internal_round_idx >= 7'd4) && (internal_round_idx <= 7'd60);

        // --- Single S-box Signals ---
        logic sbox_in_valid;
        logic sbox_in_ready;
        logic [254:0] sbox_in_payload;
        
        logic sbox_out_valid;
        logic sbox_out_ready;
        logic [254:0] sbox_out_payload;

        // --- Matrix Signals ---
        logic matrix_start;
        logic matrix_ready;
        logic matrix_done;
        logic [0:8][254:0] matrix_state_out;

        // ==========================================
        // UNICO MODMUL COMPARTILHADO (sbox <-> matriz)
        // ==========================================
        // sel_matrix: dono do modmul. A sbox e a matriz nunca rodam ao mesmo tempo
        // (FSM sequencial), entao basta selecionar pelo estado. A matriz assume o
        // modmul de START_MATRIX ate WAIT_MATRIX terminar (todos os 81 resultados
        // ja coletados quando matrix_done sobe).
        logic         sel_matrix;
        assign sel_matrix = (current_state == START_MATRIX) || (current_state == WAIT_MATRIX);

        logic         mul_valid, mul_ready, mul_res_valid;
        logic [254:0] mul_op1, mul_op2, mul_res;

        logic         sb_mul_valid, mx_mul_valid;
        logic [254:0] sb_mul_op1, sb_mul_op2, mx_mul_op1, mx_mul_op2;

        assign mul_valid = sel_matrix ? mx_mul_valid : sb_mul_valid;
        assign mul_op1   = sel_matrix ? mx_mul_op1   : sb_mul_op1;
        assign mul_op2   = sel_matrix ? mx_mul_op2   : sb_mul_op2;

        modmul #() shared_multiplier (
            .clk(clk), .rst(reset),
            .op_valid_i(mul_valid), .op_ready_o(mul_ready),
            .op1_i(mul_op1), .op2_i(mul_op2),
            .res_valid_o(mul_res_valid), .res_ready_i(1'b1), .res_o(mul_res)
        );

        // ==========================================
        // 0. AddRoundConstants via ModAdder
        // ==========================================
        logic [9:0]   seq_const_idx;
        logic [254:0] seq_selected_constant;
        logic [254:0] seq_adder_out;

        assign seq_const_idx = (internal_round_idx * 9) + sbox_idx;
        assign seq_selected_constant = ROUND_CONSTANTS[seq_const_idx];

        ModAdder #() add_round_const_seq (
            .op1_i(latched_input[sbox_idx]),
            .op2_i(seq_selected_constant),
            .res_o(seq_adder_out)
        );

        assign sbox_in_payload = seq_adder_out;

        // ==========================================
        // 1. Single S-Box Instance (sem modmul proprio)
        // ==========================================
        sbox sbox_inst (
            .io_input_valid(sbox_in_valid),
            .io_input_ready(sbox_in_ready),
            .io_input_last(1'b0), 
            .io_input_payload(sbox_in_payload),
            
            .io_output_valid(sbox_out_valid),
            .io_output_ready(sbox_out_ready),
            .io_output_payload(sbox_out_payload),

            .mul_valid_o(sb_mul_valid),
            .mul_ready_i(~sel_matrix & mul_ready),
            .mul_op1_o(sb_mul_op1),
            .mul_op2_o(sb_mul_op2),
            .mul_res_valid_i(~sel_matrix & mul_res_valid),
            .mul_res_i(mul_res),
            
            .clk(clk),
            .reset(reset)
        );

        // ==========================================
        // 2. Mix Layer Instance (sem modmul proprio)
        // ==========================================
        mix_layer_sequential #(.N(9)) mix_layer_inst (
            .clk(clk),
            .reset(reset),
            .start(matrix_start),
            .state_in(sbox_outputs), 
            .ready(matrix_ready),
            .done(matrix_done),
            .state_out(matrix_state_out),

            .mul_valid_o(mx_mul_valid),
            .mul_ready_i(sel_matrix & mul_ready),
            .mul_op1_o(mx_mul_op1),
            .mul_op2_o(mx_mul_op2),
            .mul_res_valid_i(sel_matrix & mul_res_valid),
            .mul_res_i(mul_res)
        );

        // ==========================================
        // 3. FSM Sequential Logic
        // ==========================================
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
                        if (io_input_valid) begin
                            latched_input <= io_input_payload;
                            last_reg <= io_input_last;
                            sbox_idx <= '0;
                            internal_round_idx <= '0;
                        end
                    end
                    
                    WAIT_SBOX: begin
                        if (sbox_out_valid && sbox_out_ready) begin
                            sbox_outputs[sbox_idx] <= sbox_out_payload;
                            if (sbox_idx < 4'd8) begin
                                sbox_idx <= sbox_idx + 1'b1;
                            end
                        end
                    end

                    BYPASS_SBOX: begin
                        sbox_outputs[sbox_idx] <= seq_adder_out;
                        if (sbox_idx < 4'd8) begin
                            sbox_idx <= sbox_idx + 1'b1;
                        end
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

        // ==========================================
        // 4. FSM Combinational Logic
        // ==========================================
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
                    if (io_input_valid) begin
                        next_state = FEED_SBOX;
                    end
                end
                
                FEED_SBOX: begin
                    sbox_in_valid = 1'b1;
                    if (sbox_in_ready) begin
                        next_state = WAIT_SBOX;
                    end
                end
                
                WAIT_SBOX: begin
                    sbox_out_ready = 1'b1;
                    if (sbox_out_valid) begin
                        if (sbox_idx == 4'd8) begin
                            next_state = START_MATRIX;
                        end else if (is_partial_round) begin
                            next_state = BYPASS_SBOX;
                        end else begin
                            next_state = FEED_SBOX;
                        end
                    end
                end

                BYPASS_SBOX: begin
                    if (sbox_idx == 4'd8) begin
                        next_state = START_MATRIX;
                    end else begin
                        next_state = BYPASS_SBOX;
                    end
                end
                
                START_MATRIX: begin
                    matrix_start = 1'b1;
                    if (matrix_ready) begin
                        next_state = WAIT_MATRIX;
                    end
                end
                
                WAIT_MATRIX: begin
                    if (matrix_done) begin
                        if (internal_round_idx == 7'd64) begin
                            next_state = DONE_STATE;
                        end else begin
                            next_state = FEED_SBOX;
                        end
                    end
                end

                DONE_STATE: begin
                    io_output_valid_logic = 1'b1;
                    if (io_output_ready) begin
                        next_state = IDLE;
                    end
                end
                
                default: next_state = IDLE;
            endcase
        end

        assign io_input_ready = io_input_ready_logic;
        assign io_output_valid = io_output_valid_logic;
        
        assign io_output_payload = latched_input; 
        assign io_output_last = last_reg;

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
        
        for (genvar j = 0; j < 9; j++) begin : gen_inputs
            assign io_input_valid_sboxes[j]   = io_input_valid;
            assign io_input_last_sboxes[j]    = io_input_last;
            assign io_input_payload_sboxes[j] = io_input_payload[j];
        end

        assign io_input_ready = &io_input_ready_sboxes;

        for (genvar i = 0; i < 9; i++) begin : gen_sboxes
            assign par_const_idx[i] = (round_idx * 9) + i;
            
            ModAdder #() add_round_const_par (
                .op1_i(io_input_payload_sboxes[i]),
                .op2_i(ROUND_CONSTANTS[par_const_idx[i]]),
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
                
                .clk(clk),
                .reset(reset)
            );
        end
        
        logic matrix_start;
        logic matrix_ready;
        logic matrix_done;
        logic [0:8][254:0] matrix_state_out;

        wire all_sboxes_valid = &io_output_valid_sboxes;
        assign matrix_start = all_sboxes_valid & matrix_ready;

        for (genvar k = 0; k < 9; k++) begin : gen_sbox_ready
            assign io_output_ready_sboxes[k] = matrix_start;
        end

        logic [0:8][254:0] latched_sbox_payload;

        always_ff @(posedge clk or posedge reset) begin
            if (reset) begin
                latched_sbox_payload <= '0;
            end else if (matrix_start) begin
                latched_sbox_payload <= io_output_payload_sboxes;
            end
        end

        mix_layer_sequential #(.N(9)) mix_layer_inst (
            .clk(clk),
            .reset(reset),
            .start(matrix_start),
            .state_in(latched_sbox_payload), 
            .ready(matrix_ready),
            .done(matrix_done),
            .state_out(matrix_state_out)
        );

        assign io_output_valid   = matrix_done;
        assign io_output_payload = matrix_state_out;

        reg last_reg;
        assign io_output_last = last_reg;
        always_ff @(posedge clk) begin
            if (io_input_valid && io_input_ready) begin
                last_reg <= io_input_last;
            end
        end

    end
    
endmodule