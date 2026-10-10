`timescale 1ns/1ps

// Fault detection - DECODER: x_i = A_i^-1 * y_i mod P
//
// Opera EM LUGAR sobre o registrador de estado do Poseidon (sem buffers proprios)
// e usa o multiplicador modular COMPARTILHADO do top level.
//   - start_i : pulso de 1 ciclo para iniciar
//   - done_o  : 1 ciclo quando os 9 elementos foram processados
//   - rd_*    : leitura do elemento idx do estado (combinacional)
//   - wr_*    : escrita do resultado no elemento idx do estado
module fault_decoder_out (
    input  logic         clk,
    input  logic         reset,

    input  logic         start_i,
    output logic         done_o,

    // Acesso ao registrador de estado do Poseidon
    output logic [3:0]   rd_idx_o,
    input  logic [254:0] rd_data_i,
    output logic         wr_en_o,
    output logic [3:0]   wr_idx_o,
    output logic [254:0] wr_data_o,

    // Porta do multiplicador compartilhado
    output logic         mul_valid_o,
    input  logic         mul_ready_i,
    output logic [254:0] mul_op1_o,
    output logic [254:0] mul_op2_o,
    input  logic         mul_res_valid_i,
    input  logic [254:0] mul_res_i
);

    // A_i^-1 * R mod P (forma de Montgomery). modmul(y, A^-1*R) = y * A^-1 mod P (forma normal)
    localparam logic [254:0] INV_A_MONT [0:8] = '{
        255'h2eb0c8399ccb80e7eeecb7fd521f62a8e4161ea9aaab36ab0000000055555555,
        255'h04d4237855c1011651e8dcc995bf433111b424cb999a419a0000000066666666,
        255'h66d0f1e660ec4796f8b356e005810db9e6b5824adb6cc6dadb6db6dadb6db6dc,
        255'h2c59c154f04b2e0d209627474791ca2f8396d8008ba29c5ce8ba2e8b745d1746,
        255'h521d817b8c8fe0ff7e0b745318e0fe2a40c8936413b058ebc4ec4ec462762763,
        255'h2a560940be7f68c5b1b341e3c607f697d777ea5b0f0eac3bffffffffc3c3c3c4,
        255'h1fc7355df918dde2fa9d580144e3a8d86b89bb94af2829791af286bc79435e51,
        255'h06170efc625d5398afdc17ffa689a8b1daf7c1378590c4591642c8591642c859,
        255'h70c369e0a0e579263f94f6a61a4a7b0d9a86b65af72aaac14f72c23411a7b962
    };

    typedef enum logic [1:0] { IDLE, MULTIPLY, FINISH } state_t;
    state_t state;

    logic [3:0] idx;
    logic       mul_valid;

    assign rd_idx_o    = idx;
    assign mul_valid_o = mul_valid;
    assign mul_op1_o   = rd_data_i;
    assign mul_op2_o   = INV_A_MONT[idx];

    assign wr_en_o     = (state == MULTIPLY) && mul_res_valid_i;
    assign wr_idx_o    = idx;
    assign wr_data_o   = mul_res_i;

    assign done_o      = (state == FINISH);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= IDLE;
            idx       <= '0;
            mul_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    idx <= '0;
                    if (start_i) begin
                        state     <= MULTIPLY;
                        mul_valid <= 1'b1;
                    end
                end

                MULTIPLY: begin
                    if (mul_ready_i && mul_valid)
                        mul_valid <= 1'b0;

                    if (mul_res_valid_i) begin
                        if (idx == 4'd8) begin
                            state <= FINISH;
                        end else begin
                            idx       <= idx + 1'b1;
                            mul_valid <= 1'b1;
                        end
                    end
                end

                FINISH: state <= IDLE;

                default: state <= IDLE;
            endcase
        end
    end

endmodule