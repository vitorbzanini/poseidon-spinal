// mix_layer_sequential - versao em fluxo (pipelined)
// Atualizado para Fault Detection: Seleciona dinamicamente entre matrizes Full e Partial
module mix_layer_sequential #(
    parameter int unsigned N = 9
)(
    input  logic clk,
    input  logic reset,
    input  logic start,
    input  logic is_partial_round_i,     // <--- NOVO: Recebe a flag do Top Level
    input  logic [0:N-1][254:0] state_in,
    output logic ready,
    output logic done,
    output logic [0:N-1][254:0] state_out
);

    // IMPORTAR O PACKAGE COM AS CONSTANTES DE FAULT DETECTION
    import poseidon_fault_constants_pkg::*;

    // ---------------- modmul ----------------
    logic         mul_valid, mul_ready, mul_res_valid;
    logic [254:0] mul_op1, mul_op2, mul_res;

    modmul #() matrix_multiplier (
        .clk(clk), .rst(reset),
        .op_valid_i(mul_valid), .op_ready_o(mul_ready),
        .op1_i(mul_op1), .op2_i(mul_op2),
        .res_valid_o(mul_res_valid), .res_ready_i(1'b1), .res_o(mul_res)
    );

    // ---------------- soma modular ----------------
    logic [254:0] acc_reg, mod_add_res;
    ModAdder #() adder (.op1_i(acc_reg), .op2_i(mul_res), .res_o(mod_add_res));

    // ---------------- FSM ----------------
    typedef enum logic [1:0] { IDLE, RUN, FINISH } state_t;
    state_t state;

    // lado de emissao
    logic [3:0] i_row, i_col;
    logic       issuing;           
    // lado de coleta
    logic [3:0] c_row, c_col;

    assign mul_valid = issuing;

    // NOVO: Multiplexador seleciona a matriz baseada no tipo de rodada
    always_comb begin
        if (is_partial_round_i) begin
            mul_op1 = FAULT_MDS_MATRIX_PARTIAL[i_row][i_col];
        end else begin
            mul_op1 = FAULT_MDS_MATRIX_FULL[i_row][i_col];
        end
        mul_op2 = state_in[i_col];
    end

    wire issue_fire   = mul_valid && mul_ready;
    wire collect_last = mul_res_valid && (c_col == N-1);
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= IDLE;
            issuing   <= 1'b0;
            i_row     <= '0;  i_col <= '0;
            c_row     <= '0;  c_col <= '0;
            acc_reg   <= '0;
            state_out <= '0;
        end else begin
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
                    if (mul_res_valid) begin
                        if (c_col == N-1) begin
                            state_out[c_row] <= mod_add_res;
                            acc_reg <= '0;
                            c_col   <= '0;
                            if (c_row == N-1) state <= FINISH;
                            else              c_row <= c_row + 1'b1;
                        end else begin
                            acc_reg <= mod_add_res;
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

endmodule