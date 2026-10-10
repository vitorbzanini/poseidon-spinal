`timescale 1ns/1ps

// Fault detection - ENCODER: y_i = A_i * x_i mod P
//
// Opera EM LUGAR sobre o registrador de estado do Poseidon (sem buffers proprios)
// e usa o multiplicador modular COMPARTILHADO do top level.
//   - start_i : pulso de 1 ciclo para iniciar
//   - done_o  : 1 ciclo quando os 9 elementos foram processados
//   - rd_*    : leitura do elemento idx do estado (combinacional)
//   - wr_*    : escrita do resultado no elemento idx do estado
module fault_encoder_in (
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

    // A_i * R mod P (forma de Montgomery). modmul(x, A*R) = x * A mod P (forma normal)
    localparam logic [254:0] A_MONT [0:8] = '{
        255'h486e140d064f104ecca4efcfc634efe0098e27ee0009d80600000005fffffffa,
        255'h04c9cf6d363b9de5cc83b7a7960bb7c566d9f3df00120c0b0000000afffffff5,
        255'h351332208fc5a8c4ff9c57876f8457b017e363d300189c0f0000000efffffff1,
        255'h21b85034193c413b3293bf3f18d3bf8026389fb80027601800000017ffffffe8,
        255'h5201b2e772c64c1a65ac5f1ef24c5f6ad7420fac002df01c0000001bffffffe4,
        255'h3ea6d0fafc3ce49098a3c6d69b9bc73ae5974b91003cb42500000024ffffffdb,
        255'h6ef033ae55c6ef6fcbbc66b67514672596a0bb850043442900000028ffffffd7,
        255'h5b9551c1df3d87e5feb3ce6e1e63cef5a4f5f76a0052083200000031ffffffce,
        255'h04962b3598a0adf33189fdfd9789feab1096ff40006900400000003fffffffc0
    };

    typedef enum logic [1:0] { IDLE, MULTIPLY, FINISH } state_t;
    state_t state;

    logic [3:0] idx;
    logic       mul_valid;

    assign rd_idx_o    = idx;
    assign mul_valid_o = mul_valid;
    assign mul_op1_o   = rd_data_i;
    assign mul_op2_o   = A_MONT[idx];

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