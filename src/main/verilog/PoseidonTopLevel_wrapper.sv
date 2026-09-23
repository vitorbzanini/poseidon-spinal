`include "poseidon_constants_t9.sv" 

module PoseidonTopLevel_wrapper #(
    parameter bit SEQUENTIAL = 1
)(
    input               io_input_valid,
    output              io_input_ready,
    input               io_input_last,
    
    input      [0:8][254:0] io_input_payload, 
    
    // NOVO: Necessário para saber qual constante buscar
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
        typedef enum logic [2:0] {
            IDLE,
            FEED_SBOX,
            WAIT_SBOX,
            START_MATRIX,
            WAIT_MATRIX
        } state_e;
        
        state_e current_state, next_state;

        // --- Registers & Buffers ---
        logic [3:0] sbox_idx; // Counts from 0 to 8
        logic [0:8][254:0] latched_input;
        logic [0:8][254:0] sbox_outputs;
        logic last_reg;

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
        // 0. AddRoundConstants via ModAdder
        // ==========================================
        logic [9:0]   seq_const_idx;
        logic [254:0] seq_selected_constant;
        logic [254:0] seq_adder_out;

        // Calcula o índice: (rodada atual * 9) + elemento atual
        assign seq_const_idx = (round_idx * 9) + sbox_idx;
        assign seq_selected_constant = ROUND_CONSTANTS[seq_const_idx];

        ModAdder #() add_round_const_seq (
            .op1_i(latched_input[sbox_idx]),
            .op2_i(seq_selected_constant),
            .res_o(seq_adder_out)
        );

        // Mux the latched input array + constant into the single S-box
        assign sbox_in_payload = seq_adder_out;

        // ==========================================
        // 1. Single S-Box Instance
        // ==========================================
        sbox sbox_inst (
            .io_input_valid(sbox_in_valid),
            .io_input_ready(sbox_in_ready),
            .io_input_last(1'b0), 
            .io_input_payload(sbox_in_payload),
            
            .io_output_valid(sbox_out_valid),
            .io_output_ready(sbox_out_ready),
            .io_output_payload(sbox_out_payload),
            
            .clk(clk),
            .reset(reset)
        );

        // ==========================================
        // 2. Mix Layer Instance
        // ==========================================
        mix_layer_sequential #(.N(9)) mix_layer_inst (
            .clk(clk),
            .reset(reset),
            .start(matrix_start),
            .state_in(sbox_outputs), 
            .ready(matrix_ready),
            .done(matrix_done),
            .state_out(matrix_state_out)
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
            end else begin
                current_state <= next_state;

                case (current_state)
                    IDLE: begin
                        if (io_input_valid) begin
                            latched_input <= io_input_payload;
                            last_reg <= io_input_last;
                            sbox_idx <= '0;
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
                        end else begin
                            next_state = FEED_SBOX;
                        end
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
                        io_output_valid_logic = 1'b1;
                        if (io_output_ready) begin
                            next_state = IDLE;
                        end
                    end
                end
                
                default: next_state = IDLE;
            endcase
        end

        assign io_input_ready = io_input_ready_logic;
        assign io_output_valid = io_output_valid_logic;
        assign io_output_payload = matrix_state_out;
        assign io_output_last = last_reg;

    end else begin: PARALLEL_IMPLEMENTATION

        logic [0:8] io_input_valid_sboxes;
        logic [0:8] io_input_ready_sboxes;
        logic [0:8] io_input_last_sboxes;
        logic [0:8][254:0] io_input_payload_sboxes;
        
        logic [0:8] io_output_valid_sboxes;
        logic [0:8] io_output_ready_sboxes;
        logic [0:8][254:0] io_output_payload_sboxes;
        
        // Sinais combinacionais do ModAdder
        logic [0:8][9:0]   par_const_idx;
        logic [0:8][254:0] par_adder_out;
        
        for (genvar j = 0; j < 9; j++) begin : gen_inputs
            assign io_input_valid_sboxes[j]   = io_input_valid;
            assign io_input_last_sboxes[j]    = io_input_last;
            assign io_input_payload_sboxes[j] = io_input_payload[j];
        end

        assign io_input_ready = &io_input_ready_sboxes;

        for (genvar i = 0; i < 9; i++) begin : gen_sboxes
            
            // 1. Calcula o índice para esta S-Box específica
            assign par_const_idx[i] = (round_idx * 9) + i;
            
            // 2. Instancia o somador modular para esta via do pipeline
            ModAdder #() add_round_const_par (
                .op1_i(io_input_payload_sboxes[i]),
                .op2_i(ROUND_CONSTANTS[par_const_idx[i]]),
                .res_o(par_adder_out[i])
            );

            // 3. Conecta a saída do somador na entrada da S-Box
            sbox sbox_inst (
                .io_input_valid(io_input_valid_sboxes[i]),
                .io_input_ready(io_input_ready_sboxes[i]),
                .io_input_last(io_input_last_sboxes[i]),
                .io_input_payload(par_adder_out[i]), // <- ModAdder injetado aqui
                
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