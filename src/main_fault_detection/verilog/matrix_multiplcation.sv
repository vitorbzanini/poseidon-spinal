// mix_layer_fault - versao com timing para 100 MHz
// Seleciona dinamicamente entre matrizes Full e Partial (fault detection).
//
// O que mudou em relacao a versao anterior:
//   * ANTES : a cada produto, acc = ModAdder(acc, produto)  -> soma modular de
//             255 bits (2 cadeias de carry) no laco do acumulador, e o resultado
//             ainda alimentava 9 registradores state_out (fanout).
//   * AGORA : acumula os 9 produtos SEM reduzir (1 soma simples de 259 bits por
//             ciclo, 1 cadeia de carry). A reducao mod N e feita UMA vez por
//             linha, em estagios curtos, por um redutor sequencial:
//                 x < 9N  ->  para k em {8,4,2,1}:  se x >= kN entao x -= kN
//             Cada passo usa 2 ciclos (1: subtrai e registra, 2: seleciona), entao
//             nenhuma cadeia de carry e seguida de mux/fanout no mesmo ciclo.
//             O redutor tem 9 ciclos por linha = exatamente o intervalo minimo
//             entre linhas (9 resultados do modmul por linha, 1 por ciclo).
//
// Premissa: cada resultado do modmul esta em [0, N). Vale para o modmul
// Montgomery desta base (saida = t3 >= N ? t3-N : t3, com t3 < 2N).
//
// Latencia: +9 ciclos por camada (o redutor termina 9 ciclos apos a ultima soma).
module mix_layer_fault #(
    parameter int unsigned N = 9
)(
    input  logic clk,
    input  logic reset,
    input  logic start,
    input  logic is_partial_round_i,     // Recebe a flag do Top Level
    input  logic [0:N-1][254:0] state_in,
    output logic ready,
    output logic done,
    output logic [0:N-1][254:0] state_out,

    // Porta do multiplicador COMPARTILHADO (o modmul fica no top level)
    output logic         mul_valid_o,
    input  logic         mul_ready_i,
    output logic [254:0] mul_op1_o,
    output logic [254:0] mul_op2_o,
    input  logic         mul_res_valid_i,
    input  logic [254:0] mul_res_i
);

    // IMPORTAR O PACKAGE COM AS CONSTANTES DE FAULT DETECTION
    import poseidon_fault_constants_pkg::*;

    // Modulo e multiplos usados na reducao (259 bits: 8N < 2^258)
    localparam logic [254:0] MOD_N = 255'h73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    localparam logic [258:0] N1 = {4'd0, MOD_N};
    localparam logic [258:0] N2 = {3'd0, MOD_N, 1'b0};
    localparam logic [258:0] N4 = {2'd0, MOD_N, 2'b00};
    localparam logic [258:0] N8 = {1'd0, MOD_N, 3'b000};

    // ---------------- FSM ----------------
    typedef enum logic [1:0] { IDLE, RUN, FINISH } state_t;
    state_t state;

    // lado de emissao
    logic [3:0] i_row, i_col;
    logic       issuing;
    // lado de coleta
    logic [3:0] c_row, c_col;

    assign mul_valid_o = issuing;

    // Multiplexador seleciona a matriz baseada no tipo de rodada
    always_comb begin
        if (is_partial_round_i) begin
            mul_op1_o = FAULT_MDS_MATRIX_PARTIAL[i_row][i_col];
        end else begin
            mul_op1_o = FAULT_MDS_MATRIX_FULL[i_row][i_col];
        end
        mul_op2_o = state_in[i_col];
    end

    wire issue_fire = mul_valid_o && mul_ready_i;

    // ---------------- acumulador sem reducao ----------------
    logic [258:0] acc_reg, acc_sum;
    assign acc_sum = acc_reg + {4'd0, mul_res_i};      // 1 cadeia de carry, 259 bits

    // ---------------- redutor (x < 9N  ->  x mod N) ----------------
    logic [258:0] red_x;
    logic [259:0] red_diff;                            // bit 259 = borrow
    logic [3:0]   red_cnt, red_row;
    logic         red_busy;
    logic [258:0] red_k;

    always_comb begin
        case (red_cnt)
            4'd1, 4'd2: red_k = N8;
            4'd3, 4'd4: red_k = N4;
            4'd5, 4'd6: red_k = N2;
            default:    red_k = N1;
        endcase
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= IDLE;
            issuing   <= 1'b0;
            i_row     <= '0;  i_col <= '0;
            c_row     <= '0;  c_col <= '0;
            acc_reg   <= '0;
            state_out <= '0;
            red_x     <= '0;
            red_diff  <= '0;
            red_cnt   <= '0;
            red_row   <= '0;
            red_busy  <= 1'b0;
        end else begin
            // ---- redutor: 8 passos (A: subtrai kN / B: escolhe) + 1 de escrita ----
            if (red_busy) begin
                red_cnt <= red_cnt + 1'b1;
                case (red_cnt)
                    4'd1, 4'd3, 4'd5, 4'd7: red_diff <= {1'b0, red_x} - {1'b0, red_k};
                    4'd2, 4'd4, 4'd6, 4'd8: if (!red_diff[259]) red_x <= red_diff[258:0];
                    4'd9: begin
                        state_out[red_row] <= red_x[254:0];
                        red_busy <= 1'b0;
                        if (red_row == N-1) state <= FINISH;
                    end
                    default: ;
                endcase
            end

            case (state)
                IDLE: if (start) begin
                    state   <= RUN;
                    issuing <= 1'b1;
                    i_row <= '0; i_col <= '0;
                    c_row <= '0; c_col <= '0;
                    acc_reg <= '0;
                end

                RUN: begin
                    // emissao
                    if (issue_fire) begin
                        if (i_col == N-1) begin
                            i_col <= '0;
                            if (i_row == N-1) issuing <= 1'b0;
                            else              i_row <= i_row + 1'b1;
                        end else begin
                            i_col <= i_col + 1'b1;
                        end
                    end
                    // coleta (resultados chegam em ordem)
                    if (mul_res_valid_i) begin
                        if (c_col == N-1) begin
                            // fim da linha: entrega a soma ao redutor (tem prioridade
                            // sobre o fim do redutor da linha anterior, no mesmo ciclo)
                            red_x    <= acc_sum;
                            red_cnt  <= 4'd1;
                            red_row  <= c_row;
                            red_busy <= 1'b1;
                            acc_reg  <= '0;
                            c_col    <= '0;
                            if (c_row != N-1) c_row <= c_row + 1'b1;
                        end else begin
                            acc_reg <= acc_sum;
                            c_col   <= c_col + 1'b1;
                        end
                    end
                end

                FINISH: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    assign ready = (state == IDLE);
    assign done  = (state == FINISH);

    // Somente simulacao: o redutor precisa estar livre quando a proxima linha chega
    // synthesis translate_off
    always @(posedge clk) begin
        if (!reset && state == RUN && mul_res_valid_i && c_col == N-1 && red_busy && red_cnt != 4'd9)
            $error("[%0t] mix_layer_fault: linha chegou com o redutor ocupado (cnt=%0d)", $time, red_cnt);
    end
    // synthesis translate_on

endmodule