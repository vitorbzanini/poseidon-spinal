`timescale 1ns/1ps

// =============================================================================
// Poseidon + Fault Detection  --  versao com UM UNICO multiplicador modular
//
// Fluxo:  entrada -> ENCODER (x_i*A_i) -> 65 rodadas -> DECODER (y_i*A_i^-1) -> saida
//
//  * Existe UM modmul (shared_mult) para o design inteiro. S-box, camada de
//    matriz, encoder e decoder so requisitam o multiplicador; nunca dois ao mesmo
//    tempo (as fases sao separadas pela FSM).
//  * Existe UM registrador de estado (latched_input). O encoder e o decoder
//    operam em lugar sobre ele; a saida e lida dele. Nao ha buffers extras.
//
// Configuracao do multiplicador (VERSION / PIPELINE): dentro do modmul.sv
// =============================================================================
module PoseidonTopLevel_wrapper #(
    parameter bit SEQUENTIAL = 1   // Somente a arquitetura sequencial e suportada
)(
    input               io_input_valid,
    output              io_input_ready,
    input               io_input_last,

    input      [0:8][254:0] io_input_payload,

    input      [6:0]        round_idx,   // nao usado na versao sequencial

    output              io_output_valid,
    input               io_output_ready,
    output              io_output_last,

    output     [0:8][254:0] io_output_payload,

    input               clk,
    input               reset
);

    import poseidon_fault_constants_pkg::*;

    if (!SEQUENTIAL) begin: UNSUPPORTED
        $error("PoseidonTopLevel_wrapper: a versao paralela nao foi adaptada ao multiplicador compartilhado");
    end

    // ==========================================
    // MULTIPLICADOR MODULAR COMPARTILHADO
    // ==========================================
    logic         shared_valid, shared_ready, shared_res_valid;
    logic [254:0] shared_op1, shared_op2, shared_res;

    modmul #() shared_mult (
        .clk(clk), .rst(reset),
        .op_valid_i(shared_valid), .op_ready_o(shared_ready),
        .op1_i(shared_op1), .op2_i(shared_op2),
        .res_valid_o(shared_res_valid), .res_ready_i(1'b1), .res_o(shared_res)
    );

    // Requisicoes dos 4 clientes
    logic         enc_mul_valid, dec_mul_valid, sb_mul_valid, mx_mul_valid;
    logic [254:0] enc_mul_op1, enc_mul_op2;
    logic [254:0] dec_mul_op1, dec_mul_op2;
    logic [254:0] sb_mul_op1,  sb_mul_op2;
    logic [254:0] mx_mul_op1,  mx_mul_op2;

    // Arbitragem: so um cliente requisita por vez (one-hot), entao basta AND-OR
    logic [3:0] mul_req;
    assign mul_req = {mx_mul_valid, sb_mul_valid, dec_mul_valid, enc_mul_valid};

    assign shared_valid = |mul_req;
    assign shared_op1   = ({255{enc_mul_valid}} & enc_mul_op1) |
                          ({255{dec_mul_valid}} & dec_mul_op1) |
                          ({255{sb_mul_valid }} & sb_mul_op1 ) |
                          ({255{mx_mul_valid }} & mx_mul_op1 );
    assign shared_op2   = ({255{enc_mul_valid}} & enc_mul_op2) |
                          ({255{dec_mul_valid}} & dec_mul_op2) |
                          ({255{sb_mul_valid }} & sb_mul_op2 ) |
                          ({255{mx_mul_valid }} & mx_mul_op2 );

    // Dono do multiplicador: guarda quem fez a ultima requisicao, para
    // devolver o resultado so a ele (inclusive com varias operacoes em voo)
    typedef enum logic [1:0] { OWN_ENC, OWN_DEC, OWN_SBOX, OWN_MIX } owner_e;
    owner_e owner;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) owner <= OWN_ENC;
        else if (|mul_req) begin
            if      (enc_mul_valid) owner <= OWN_ENC;
            else if (dec_mul_valid) owner <= OWN_DEC;
            else if (sb_mul_valid)  owner <= OWN_SBOX;
            else                    owner <= OWN_MIX;
        end
    end

    logic enc_res_valid, dec_res_valid, sb_res_valid, mx_res_valid;
    assign enc_res_valid = shared_res_valid && (owner == OWN_ENC);
    assign dec_res_valid = shared_res_valid && (owner == OWN_DEC);
    assign sb_res_valid  = shared_res_valid && (owner == OWN_SBOX);
    assign mx_res_valid  = shared_res_valid && (owner == OWN_MIX);

    // Somente para simulacao: dois clientes requisitando juntos = bug de FSM
    // synthesis translate_off
    always @(posedge clk) begin
        if ($countones(mul_req) > 1)
            $error("[%0t] mais de um cliente requisitou o multiplicador: %b", $time, mul_req);
    end
    // synthesis translate_on

    // ==========================================
    // ESTADO DO POSEIDON (registrador unico)
    // ==========================================
    typedef enum logic [3:0] {
        IDLE,
        ENCODE_START, ENCODE_WAIT,
        FEED_SBOX, WAIT_SBOX, BYPASS_SBOX,
        START_MATRIX, WAIT_MATRIX,
        DECODE_START, DECODE_WAIT,
        OUTPUT_STATE
    } state_e;

    state_e current_state, next_state;

    logic [6:0] internal_round_idx;
    logic [3:0] sbox_idx;
    logic [0:8][254:0] latched_input;   // estado: entrada -> encoded -> rodadas -> decoded -> saida
    logic [0:8][254:0] sbox_outputs;
    logic last_reg;

    logic is_partial_round;
    assign is_partial_round = (internal_round_idx >= 7'd4) && (internal_round_idx <= 7'd60);

    // ---------------- Encoder / Decoder ----------------
    logic        enc_start, enc_done, dec_start, dec_done;
    logic [3:0]  enc_rd_idx, dec_rd_idx;
    logic        enc_wr_en, dec_wr_en;
    logic [3:0]  enc_wr_idx, dec_wr_idx;
    logic [254:0] enc_wr_data, dec_wr_data;

    // Leitura compartilhada do estado (um unico mux 9:1)
    logic [3:0]   scale_rd_idx;
    logic [254:0] scale_rd_data;
    assign scale_rd_idx  = (current_state == DECODE_WAIT) ? dec_rd_idx : enc_rd_idx;
    assign scale_rd_data = latched_input[scale_rd_idx];

    assign enc_start = (current_state == ENCODE_START);
    assign dec_start = (current_state == DECODE_START);

    fault_encoder_in encoder_inst (
        .clk(clk), .reset(reset),
        .start_i(enc_start), .done_o(enc_done),
        .rd_idx_o(enc_rd_idx), .rd_data_i(scale_rd_data),
        .wr_en_o(enc_wr_en), .wr_idx_o(enc_wr_idx), .wr_data_o(enc_wr_data),
        .mul_valid_o(enc_mul_valid), .mul_ready_i(shared_ready),
        .mul_op1_o(enc_mul_op1), .mul_op2_o(enc_mul_op2),
        .mul_res_valid_i(enc_res_valid), .mul_res_i(shared_res)
    );

    fault_decoder_out decoder_inst (
        .clk(clk), .reset(reset),
        .start_i(dec_start), .done_o(dec_done),
        .rd_idx_o(dec_rd_idx), .rd_data_i(scale_rd_data),
        .wr_en_o(dec_wr_en), .wr_idx_o(dec_wr_idx), .wr_data_o(dec_wr_data),
        .mul_valid_o(dec_mul_valid), .mul_ready_i(shared_ready),
        .mul_op1_o(dec_mul_op1), .mul_op2_o(dec_mul_op2),
        .mul_res_valid_i(dec_res_valid), .mul_res_i(shared_res)
    );

    // ---------------- S-box ----------------
    logic sbox_in_valid, sbox_in_ready;
    logic [254:0] sbox_in_payload;

    logic sbox_out_valid, sbox_out_ready;
    logic [254:0] sbox_out_payload;

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
        .clk(clk), .reset(reset),
        .mul_valid_o(sb_mul_valid), .mul_ready_i(shared_ready),
        .mul_op1_o(sb_mul_op1), .mul_op2_o(sb_mul_op2),
        .mul_res_valid_i(sb_res_valid), .mul_res_i(shared_res)
    );

    // ---------------- Camada de matriz ----------------
    logic matrix_start, matrix_ready, matrix_done;
    logic [0:8][254:0] matrix_state_out;

    mix_layer_sequential #(.N(9)) mix_layer_inst (
        .clk(clk), .reset(reset),
        .start(matrix_start),
        .is_partial_round_i(is_partial_round),
        .state_in(sbox_outputs),
        .ready(matrix_ready),
        .done(matrix_done),
        .state_out(matrix_state_out),
        .mul_valid_o(mx_mul_valid), .mul_ready_i(shared_ready),
        .mul_op1_o(mx_mul_op1), .mul_op2_o(mx_mul_op2),
        .mul_res_valid_i(mx_res_valid), .mul_res_i(shared_res)
    );

    // ---------------- Registradores ----------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state      <= IDLE;
            sbox_idx           <= '0;
            latched_input      <= '0;
            sbox_outputs       <= '0;
            last_reg           <= 1'b0;
            internal_round_idx <= '0;
        end else begin
            current_state <= next_state;

            case (current_state)
                IDLE: begin
                    if (io_input_valid) begin
                        latched_input      <= io_input_payload;
                        last_reg           <= io_input_last;
                        sbox_idx           <= '0;
                        internal_round_idx <= '0;
                    end
                end
                ENCODE_WAIT: begin
                    if (enc_wr_en) latched_input[enc_wr_idx] <= enc_wr_data;
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
                DECODE_WAIT: begin
                    if (dec_wr_en) latched_input[dec_wr_idx] <= dec_wr_data;
                end
                default: ;
            endcase
        end
    end

    // ---------------- FSM ----------------
    always_comb begin
        next_state     = current_state;
        sbox_in_valid  = 1'b0;
        sbox_out_ready = 1'b0;
        matrix_start   = 1'b0;

        case (current_state)
            IDLE: begin
                if (io_input_valid) next_state = ENCODE_START;
            end
            ENCODE_START: next_state = ENCODE_WAIT;
            ENCODE_WAIT: begin
                if (enc_done) next_state = FEED_SBOX;
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
                    if (internal_round_idx == 7'd64) next_state = DECODE_START;
                    else next_state = FEED_SBOX;
                end
            end
            DECODE_START: next_state = DECODE_WAIT;
            DECODE_WAIT: begin
                if (dec_done) next_state = OUTPUT_STATE;
            end
            OUTPUT_STATE: begin
                if (io_output_ready) next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // ---------------- Interface ----------------
    assign io_input_ready    = (current_state == IDLE);
    assign io_output_valid   = (current_state == OUTPUT_STATE);
    assign io_output_payload = latched_input;
    assign io_output_last    = last_reg;

endmodule