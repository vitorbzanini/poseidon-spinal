// mix_layer_sequential - versao em fluxo (pipelined)
// Matriz MDS e Hankel: M[i][j] = v[i+j] (17 valores distintos).
// Os valores ja vem em forma de Montgomery (v*R mod N, R=2^256), pre-computados
// offline. Assim cada elemento precisa de UM modmul (antes eram dois):
//   modmul(M_bar, s) = M*R*s*R^-1 = M*s mod N
// As 81 multiplicacoes da camada sao emitidas em sequencia (back-to-back) e os
// resultados sao acumulados na ordem em que saem do pipeline.
module mix_layer_sequential #(
    parameter int unsigned N = 9
)(
    input  logic clk,
    input  logic reset,
    input  logic start,
    input  logic [0:N-1][254:0] state_in,
    output logic ready,
    output logic done,
    output logic [0:N-1][254:0] state_out
);

    localparam [254:0] MBAR [0:16] = '{
        255'h5cd95cf5500229281c7578047721063bd930778fe38d4f8daaaaaaaa1c71c71d,  // M[i+j=0] * R mod N
        255'h026a11bc2ae0808b28f46e64cadfa19888da1265cccd20cd0000000033333333,  // M[i+j=1] * R mod N
        255'h2c59c154f04b2e0d209627474791ca2f8396d8008ba29c5ce8ba2e8b745d1746,  // M[i+j=2] * R mod N
        255'h629e6f8cc668fe30222690055bc13aae37d3c2acaaa992a9ffffffff55555556,  // M[i+j=3] * R mod N
        255'h521d817b8c8fe0ff7e0b745318e0fe2a40c8936413b058ebc4ec4ec462762763,  // M[i+j=4] * R mod N
        255'h336878f3307623cb7c59ab7002c086dcf35ac1256db6636d6db6db6d6db6db6e,  // M[i+j=5] * R mod N
        255'h4ee5260a3853fe8ce81ed99de300fbbe930fcef08887a887ffffffff77777778,  // M[i+j=6] * R mod N
        255'h1000000000000000000000000000000000000000000000000000000000000000,  // M[i+j=7] * R mod N
        255'h2a560940be7f68c5b1b341e3c607f697d777ea5b0f0eac3bffffffffc3c3c3c4,  // M[i+j=8] * R mod N
        255'h686382243ccfd33827d7a80640616f2096770dc971c5d5c6555555548e38e38f,  // M[i+j=9] * R mod N
        255'h1fc7355df918dde2fa9d580144e3a8d86b89bb94af2829791af286bc79435e51,  // M[i+j=10] * R mod N
        255'h3b2bdc87aa3efee9ae1723366a40bcceee4bdb346665be65ffffffff9999999a,  // M[i+j=11] * R mod N
        255'h48ea33132e2dec4a63f9ba4d5a60f73fbe266219f3ce60f3492492489e79e79f,  // M[i+j=12] * R mod N
        255'h162ce0aa78259706904b13a3a3c8e517c1cb6c0045d14e2e745d1745ba2e8ba3,  // M[i+j=13] * R mod N
        255'h06170efc625d5398afdc17ffa689a8b1daf7c1378590c4591642c8591642c859,  // M[i+j=14] * R mod N
        255'h314f37c663347f1811134802ade09d571be9e1565554c954ffffffffaaaaaaab,  // M[i+j=15] * R mod N
        255'h1826c228b312e612e76d575d1fe038a47ab05b5c851e85eb6666666647ae147b  // M[i+j=16] * R mod N

    };

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
    logic       issuing;           // ainda ha operacoes a emitir
    // lado de coleta
    logic [3:0] c_row, c_col;

    assign mul_valid = issuing;

    wire [4:0] mbar_idx = {1'b0, i_row} + {1'b0, i_col};  // 5 bits: máx 8+8=16
    assign mul_op1 = MBAR[mbar_idx];
    assign mul_op2   = state_in[i_col];

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