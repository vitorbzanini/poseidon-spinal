`timescale 1ns/1ps

module fault_decoder_out (
    input  logic               clk,
    input  logic               reset,

    input  logic               io_input_valid,
    output logic               io_input_ready,
    input  logic [0:8][254:0]  io_input_payload,

    output logic               io_output_valid,
    input  logic               io_output_ready,
    output logic [0:8][254:0]  io_output_payload
);

    // Inversos de A em forma de Montgomery: (A^-1 * R) mod P
    // modmul(y, A^-1 * R) = y * A^-1 * R * R^-1 = y * A^-1 mod P
    localparam logic [254:0] INV_A_SCALARS [0:8] = '{
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

    typedef enum logic [1:0] { IDLE, MULTIPLY, DONE } state_t;
    state_t state;

    logic [3:0] idx; 
    logic [0:8][254:0] latched_in;
    logic [0:8][254:0] latched_out;

    logic         mul_valid, mul_ready, mul_res_valid;
    logic [254:0] mul_op1, mul_op2, mul_res;

    modmul #() decoder_mult (
        .clk(clk), .rst(reset),
        .op_valid_i(mul_valid), .op_ready_o(mul_ready),
        .op1_i(mul_op1), .op2_i(mul_op2),
        .res_valid_o(mul_res_valid), .res_ready_i(1'b1), .res_o(mul_res)
    );

    // Entrada em Montgomery (X * R) multiplicada pelo inverso puro (INV_A)
    // O modmul aplica R^-1, resultando em X * INV_A na forma normal.
    assign mul_op1 = latched_in[idx];
    assign mul_op2 = INV_A_SCALARS[idx];

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
                    if (mul_ready && mul_valid) begin
                        mul_valid <= 1'b0; 
                    end

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
                    if (io_output_ready) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    assign io_input_ready    = (state == IDLE);
    assign io_output_valid   = (state == DONE);
    assign io_output_payload = latched_out;

endmodule