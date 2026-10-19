`timescale 1ns/1ps

// =============================================================================
// PoseidonSequentialShared_top
//
// Poseidon padrao + Poseidon codificado (fault detection) em UM UNICO motor,
// executados em sequencia sobre a mesma entrada:
//
//   Passo 1 (modo padrao):    entrada -> 65 rodadas -> resultado guardado em res_reg
//   Passo 2 (modo codificado): entrada -> ENCODER -> 65 rodadas -> DECODER
//   Final: compara o resultado decodificado com res_reg. Se diferir, falha.
//
// Compartilhado entre os dois passos:
//   * 1 modmul (arbitrado entre sbox, camadas de matriz, encoder e decoder)
//   * 1 sbox, 1 ModAdder de round constants
//   * 1 registrador de estado (latched_input) e 1 de saida da sbox (sbox_outputs)
//   * 1 FSM
//
// Duplicado (so existe um de cada modo):
//   * mix_layer_standard / mix_layer_fault  (tabela de matriz diferente em cada modo)
//   * tabelas de round constants (ROUND_CONSTANTS / FAULT_ROUND_CONSTANTS)
//   * encoder / decoder so existem para o modo codificado
//
// Registradores extras do modo "dois passos": input_reg (entrada original, para
// o passo 2) e res_reg (resultado do passo 1, para comparar).
//
// Interface identica ao TopLevelPoseidon (comparador paralelo).
//
// Timing (100 MHz): registro na saida do modmul, AddRoundConstants em pipeline
// (estado ADD_RC, 4 ciclos) e camadas de matriz com acumulacao sem reducao.
// =============================================================================
module PoseidonSequentialShared_top #(
    parameter bit ERROR_ON_FAULT = 1   // 0 = so sinaliza fault_detected_o, sem $error
)(
    input               io_input_valid,
    output              io_input_ready,
    input               io_input_last,
    input      [0:8][254:0] io_input_payload,
    input      [6:0]        round_idx,   // nao usado (compatibilidade)

    output              io_output_valid,
    input               io_output_ready,
    output              io_output_last,
    output     [0:8][254:0] io_output_payload,   // resultado do Poseidon padrao

    // ---- deteccao de falha ----
    output              fault_detected_o,
    output     [0:8]    fault_mask_o,
    output logic        fault_sticky_o,

    input               clk,
    input               reset
);

    import poseidon_constants_standard_pkg::ROUND_CONSTANTS;
    import poseidon_fault_constants_pkg::FAULT_ROUND_CONSTANTS;
    import poseidon_pi_pkg::SIGMA;
    import poseidon_pi_pkg::SBOX_POS_PARTIAL;

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

    // Estagio de registro na saida do modmul (corte de timing).
    // Separa "saida do modmul -> AND-OR dos clientes" de "-> ModAdder da matriz".
    // Custa 1 ciclo por multiplicacao; todos os clientes esperam res_valid,
    // entao a FSM nao muda.
    logic         shared_res_valid_q;
    logic [254:0] shared_res_q;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) shared_res_valid_q <= 1'b0;
        else       shared_res_valid_q <= shared_res_valid;
    end
    always_ff @(posedge clk) shared_res_q <= shared_res;

    // Clientes: encoder, decoder, sbox, matriz padrao, matriz codificada
    logic         enc_mul_valid, dec_mul_valid, sb_mul_valid, mxs_mul_valid, mxf_mul_valid;
    logic [254:0] enc_mul_op1, enc_mul_op2;
    logic [254:0] dec_mul_op1, dec_mul_op2;
    logic [254:0] sb_mul_op1,  sb_mul_op2;
    logic [254:0] mxs_mul_op1, mxs_mul_op2;
    logic [254:0] mxf_mul_op1, mxf_mul_op2;

    // Um cliente por vez (one-hot) -> AND-OR
    logic [4:0] mul_req;
    assign mul_req = {mxf_mul_valid, mxs_mul_valid, sb_mul_valid, dec_mul_valid, enc_mul_valid};

    assign shared_valid = |mul_req;
    assign shared_op1   = ({255{enc_mul_valid }} & enc_mul_op1 ) |
                          ({255{dec_mul_valid }} & dec_mul_op1 ) |
                          ({255{sb_mul_valid  }} & sb_mul_op1  ) |
                          ({255{mxs_mul_valid }} & mxs_mul_op1 ) |
                          ({255{mxf_mul_valid }} & mxf_mul_op1 );
    assign shared_op2   = ({255{enc_mul_valid }} & enc_mul_op2 ) |
                          ({255{dec_mul_valid }} & dec_mul_op2 ) |
                          ({255{sb_mul_valid  }} & sb_mul_op2  ) |
                          ({255{mxs_mul_valid }} & mxs_mul_op2 ) |
                          ({255{mxf_mul_valid }} & mxf_mul_op2 );

    // Dono do multiplicador: quem fez a ultima requisicao recebe os resultados
    typedef enum logic [2:0] { OWN_ENC, OWN_DEC, OWN_SBOX, OWN_MIX_STD, OWN_MIX_FLT } owner_e;
    owner_e owner;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) owner <= OWN_ENC;
        else if (|mul_req) begin
            if      (enc_mul_valid) owner <= OWN_ENC;
            else if (dec_mul_valid) owner <= OWN_DEC;
            else if (sb_mul_valid)  owner <= OWN_SBOX;
            else if (mxs_mul_valid) owner <= OWN_MIX_STD;
            else                    owner <= OWN_MIX_FLT;
        end
    end

    logic enc_res_valid, dec_res_valid, sb_res_valid, mxs_res_valid, mxf_res_valid;
    assign enc_res_valid = shared_res_valid_q && (owner == OWN_ENC);
    assign dec_res_valid = shared_res_valid_q && (owner == OWN_DEC);
    assign sb_res_valid  = shared_res_valid_q && (owner == OWN_SBOX);
    assign mxs_res_valid = shared_res_valid_q && (owner == OWN_MIX_STD);
    assign mxf_res_valid = shared_res_valid_q && (owner == OWN_MIX_FLT);

    // synthesis translate_off
    always @(posedge clk) begin
        if ($countones(mul_req) > 1)
            $error("[%0t] mais de um cliente requisitou o multiplicador: %b", $time, mul_req);
    end
    // synthesis translate_on

    // ==========================================
    // ESTADO
    // ==========================================
    typedef enum logic [3:0] {
        IDLE,
        ADD_RC,
        FEED_SBOX, WAIT_SBOX, BYPASS_SBOX,
        START_MATRIX, WAIT_MATRIX,
        LOAD_FAULT,
        ENCODE_START, ENCODE_WAIT,
        DECODE_START, DECODE_WAIT,
        OUTPUT_STATE
    } state_e;

    state_e current_state, next_state;

    logic        fault_mode;           // 0 = passo padrao, 1 = passo codificado
    logic [6:0]  internal_round_idx;
    logic [3:0]  sbox_idx;
    logic [0:8][254:0] latched_input;  // estado de trabalho (os dois passos)
    logic [0:8][254:0] sbox_outputs;
    logic [0:8][254:0] input_reg;      // entrada original (para o passo 2)
    logic [0:8][254:0] res_reg;        // resultado do passo 1 (padrao)
    logic last_reg;

    logic is_partial_round;
    assign is_partial_round = (internal_round_idx >= 7'd4) && (internal_round_idx <= 7'd60);

    // ---------------- Encoder / Decoder ----------------
    logic        enc_start, enc_done, dec_start, dec_done;
    logic [3:0]  enc_rd_idx, dec_rd_idx;
    logic        enc_wr_en, dec_wr_en;
    logic [3:0]  enc_wr_idx, dec_wr_idx;
    logic [254:0] enc_wr_data, dec_wr_data;

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
        .mul_res_valid_i(enc_res_valid), .mul_res_i(shared_res_q)
    );

    fault_decoder_out decoder_inst (
        .clk(clk), .reset(reset),
        .start_i(dec_start), .done_o(dec_done),
        .rd_idx_o(dec_rd_idx), .rd_data_i(scale_rd_data),
        .wr_en_o(dec_wr_en), .wr_idx_o(dec_wr_idx), .wr_data_o(dec_wr_data),
        .mul_valid_o(dec_mul_valid), .mul_ready_i(shared_ready),
        .mul_op1_o(dec_mul_op1), .mul_op2_o(dec_mul_op2),
        .mul_res_valid_i(dec_res_valid), .mul_res_i(shared_res_q)
    );

    // ---------------- Round constants + S-box (compartilhados) ----------------
    logic sbox_in_valid, sbox_in_ready;
    logic [254:0] sbox_in_payload;
    logic sbox_out_valid, sbox_out_ready;
    logic [254:0] sbox_out_payload;

    // ---------------- AddRoundConstants em PIPELINE (4 ciclos, estado ADD_RC) ----------------
    //   ciclo 1: seq_const_idx (= round*9+idx) e rc_x_q (mux 9:1 do estado)
    //   ciclo 2: seq_selected_constant (ROM de constantes)
    //   ciclo 3-4: ModAdder_pipe (2 estagios) -> seq_adder_out
    // Os registradores seguem as entradas continuamente; o FSM espera 4 ciclos em
    // ADD_RC antes de usar seq_adder_out.
    logic [9:0]   seq_const_idx;
    logic [254:0] seq_selected_constant, seq_adder_out;
    logic [254:0] rc_x_q;
    logic [1:0]   rc_cnt;

    always_ff @(posedge clk) begin
        seq_const_idx         <= (internal_round_idx * 9) + sbox_idx;
        rc_x_q                <= latched_input[sbox_idx];
        seq_selected_constant <= fault_mode ? FAULT_ROUND_CONSTANTS[seq_const_idx]
                                      : ROUND_CONSTANTS[seq_const_idx];
    end

    ModAdder_pipe #() add_round_const_seq (
        .clk(clk),
        .op1_i(rc_x_q),
        .op2_i(seq_selected_constant),
        .res_o(seq_adder_out)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset)                         rc_cnt <= 2'd0;
        else if (current_state == ADD_RC)  rc_cnt <= rc_cnt + 2'd1;
        else                               rc_cnt <= 2'd0;
    end

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
        .mul_res_valid_i(sb_res_valid), .mul_res_i(shared_res_q)
    );

    // ---------------- Camadas de matriz (uma por modo) ----------------
    logic matrix_start, matrix_ready, matrix_done;
    logic [0:8][254:0] matrix_state_out;

    logic mxs_ready, mxs_done, mxf_ready, mxf_done;
    logic [0:8][254:0] mxs_state_out, mxf_state_out;

    mix_layer_standard #(.N(9)) mix_std_inst (
        .clk(clk), .reset(reset),
        .start(matrix_start & ~fault_mode),
        .state_in(sbox_outputs),
        .ready(mxs_ready), .done(mxs_done), .state_out(mxs_state_out),
        .mul_valid_o(mxs_mul_valid), .mul_ready_i(shared_ready),
        .mul_op1_o(mxs_mul_op1), .mul_op2_o(mxs_mul_op2),
        .mul_res_valid_i(mxs_res_valid), .mul_res_i(shared_res_q)
    );

    mix_layer_fault #(.N(9)) mix_flt_inst (
        .clk(clk), .reset(reset),
        .start(matrix_start & fault_mode),
        .is_partial_round_i(is_partial_round),
        .state_in(sbox_outputs),
        .ready(mxf_ready), .done(mxf_done), .state_out(mxf_state_out),
        .mul_valid_o(mxf_mul_valid), .mul_ready_i(shared_ready),
        .mul_op1_o(mxf_mul_op1), .mul_op2_o(mxf_mul_op2),
        .mul_res_valid_i(mxf_res_valid), .mul_res_i(shared_res_q)
    );

    assign matrix_ready     = fault_mode ? mxf_ready     : mxs_ready;
    assign matrix_done      = fault_mode ? mxf_done      : mxs_done;
    assign matrix_state_out = fault_mode ? mxf_state_out : mxs_state_out;

    // ---------------- Quem passa pelo S-box nas partial rounds ----------------
    // Modo padrao: so a posicao 0. Modo codificado: SBOX_POS_PARTIAL.
    logic [3:0] sbox_pos;
    assign sbox_pos = fault_mode ? 4'(SBOX_POS_PARTIAL) : 4'd0;

    // Em partial round so a posicao sbox_pos passa pelo S-box; as outras fazem bypass
    logic elem_uses_sbox;
    assign elem_uses_sbox = !is_partial_round || (sbox_idx == sbox_pos);

    // ---------------- Permutacao (so no modo codificado) ----------------
    logic [0:8][254:0] permuted_input;
    for (genvar k = 0; k < 9; k++) begin : INPUT_PERMUTE
        assign permuted_input[k] = input_reg[SIGMA[k]];
    end

    // ---------------- Registradores ----------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state      <= IDLE;
            fault_mode         <= 1'b0;
            sbox_idx           <= '0;
            latched_input      <= '0;
            sbox_outputs       <= '0;
            input_reg          <= '0;
            res_reg            <= '0;
            last_reg           <= 1'b0;
            internal_round_idx <= '0;
        end else begin
            current_state <= next_state;

            case (current_state)
                IDLE: begin
                    if (io_input_valid) begin
                        input_reg          <= io_input_payload;
                        latched_input      <= io_input_payload;   // passo padrao: sem permutacao
                        fault_mode         <= 1'b0;
                        last_reg           <= io_input_last;
                        sbox_idx           <= '0;
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
                        if (!fault_mode && internal_round_idx == 7'd64)
                            res_reg <= matrix_state_out;          // fim do passo 1
                        else
                            latched_input <= matrix_state_out;
                        if (internal_round_idx < 7'd64) begin
                            internal_round_idx <= internal_round_idx + 1'b1;
                            sbox_idx <= '0;
                        end
                    end
                end
                LOAD_FAULT: begin                                  // inicio do passo 2
                    latched_input      <= permuted_input;
                    fault_mode         <= 1'b1;
                    sbox_idx           <= '0;
                    internal_round_idx <= '0;
                end
                ENCODE_WAIT: begin
                    if (enc_wr_en) latched_input[enc_wr_idx] <= enc_wr_data;
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
                if (io_input_valid) next_state = ADD_RC;
            end
            ADD_RC: begin
                if (rc_cnt == 2'd3)
                    next_state = elem_uses_sbox ? FEED_SBOX : BYPASS_SBOX;
            end
            FEED_SBOX: begin
                sbox_in_valid = 1'b1;
                if (sbox_in_ready) next_state = WAIT_SBOX;
            end
            WAIT_SBOX: begin
                sbox_out_ready = 1'b1;
                if (sbox_out_valid) begin
                    if (sbox_idx == 4'd8) next_state = START_MATRIX;
                    else next_state = ADD_RC;
                end
            end
            BYPASS_SBOX: begin
                if (sbox_idx == 4'd8) next_state = START_MATRIX;
                else next_state = ADD_RC;
            end
            START_MATRIX: begin
                matrix_start = 1'b1;
                if (matrix_ready) next_state = WAIT_MATRIX;
            end
            WAIT_MATRIX: begin
                if (matrix_done) begin
                    if (internal_round_idx == 7'd64)
                        next_state = fault_mode ? DECODE_START : LOAD_FAULT;
                    else
                        next_state = ADD_RC;
                end
            end
            LOAD_FAULT:   next_state = ENCODE_START;
            ENCODE_START: next_state = ENCODE_WAIT;
            ENCODE_WAIT: begin
                if (enc_done) next_state = ADD_RC;
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

    // ---------------- Comparacao e saida ----------------
    // latched_input guarda o resultado codificado->decodificado na ordem
    // permutada: posicao k = elemento original SIGMA[k].
    logic [0:8] elem_mismatch;
    for (genvar k = 0; k < 9; k++) begin : CMP
        assign elem_mismatch[SIGMA[k]] = (latched_input[k] != res_reg[SIGMA[k]]);
    end

    logic out_valid_int;
    assign out_valid_int = (current_state == OUTPUT_STATE);

    assign io_input_ready    = (current_state == IDLE);
    assign io_output_valid   = out_valid_int;
    assign io_output_payload = res_reg;
    assign io_output_last    = last_reg;

    assign fault_mask_o     = out_valid_int ? elem_mismatch : '0;
    assign fault_detected_o = out_valid_int & (|elem_mismatch);

    always_ff @(posedge clk or posedge reset) begin
        if (reset)                 fault_sticky_o <= 1'b0;
        else if (fault_detected_o) fault_sticky_o <= 1'b1;
    end

    // synthesis translate_off
    always @(posedge clk) begin
        if (ERROR_ON_FAULT && fault_detected_o && io_output_ready)
            $error("[%0t] FALHA DETECTADA: saidas divergem. mask=%b", $time, fault_mask_o);
    end
    // synthesis translate_on

endmodule