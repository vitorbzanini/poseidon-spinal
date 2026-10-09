`timescale 1ns/1ps

module fault_encoder_in (
    input  logic               clk,
    input  logic               reset,

    input  logic               io_input_valid,
    output logic               io_input_ready,
    input  logic [0:8][254:0]  io_input_payload,

    output logic               io_output_valid,
    input  logic               io_output_ready,
    output logic [0:8][254:0]  io_output_payload
);

    // A_i * R mod P  (Montgomery form of A_i).
    // modmul(x, A*R) = x * A * R * R^-1 = x * A mod P  -> result in normal form
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

    typedef enum logic [1:0] { IDLE, MULTIPLY, DONE } state_t;
    state_t state;

    logic [3:0] idx;
    logic [0:8][254:0] latched_in;
    logic [0:8][254:0] latched_out;

    logic         mul_valid, mul_ready, mul_res_valid;
    logic [254:0] mul_op1, mul_op2, mul_res;

    modmul #() encoder_mult (
        .clk(clk), .rst(reset),
        .op_valid_i(mul_valid), .op_ready_o(mul_ready),
        .op1_i(mul_op1), .op2_i(mul_op2),
        .res_valid_o(mul_res_valid), .res_ready_i(1'b1), .res_o(mul_res)
    );

    assign mul_op1 = latched_in[idx];
    assign mul_op2 = A_MONT[idx];

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= IDLE;
            idx         <= '0;
            latched_in  <= '0;
            latched_out <= '0;
            mul_valid   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    idx <= '0;
                    if (io_input_valid) begin
                        latched_in <= io_input_payload;
                        state      <= MULTIPLY;
                        mul_valid  <= 1'b1;
                    end
                end

                MULTIPLY: begin
                    if (mul_ready && mul_valid)
                        mul_valid <= 1'b0;

                    if (mul_res_valid) begin
                        latched_out[idx] <= mul_res;
                        if (idx == 4'd8) begin
                            state <= DONE;
                        end else begin
                            idx       <= idx + 1'b1;
                            mul_valid <= 1'b1;
                        end
                    end
                end

                DONE: begin
                    if (io_output_ready)
                        state <= IDLE;
                end
            endcase
        end
    end

    assign io_input_ready     = (state == IDLE);
    assign io_output_valid    = (state == DONE);
    assign io_output_payload  = latched_out;

endmodule