`timescale 1ns/1ps

// sbox serial (x^5) SEM modmul interno.
// A multiplicacao modular e feita por um modmul externo (compartilhado no top).
module sbox (
    input               io_input_valid,
    output              io_input_ready,
    input               io_input_last,
    input      [254:0]  io_input_payload,
    output              io_output_valid,
    input               io_output_ready,
    output     [254:0]  io_output_payload,

    // interface com o modmul compartilhado
    output              mul_valid_o,
    input               mul_ready_i,
    output logic [254:0] mul_op1_o,
    output logic [254:0] mul_op2_o,
    input               mul_res_valid_i,
    input      [254:0]  mul_res_i,

    input               clk,
    input               reset
);

    localparam [254:0] R2_MOD_N = 255'h0748d9d99f59ff1105d314967254398f2b6cedcb87925c23c999e990f3f29c6d;

    typedef enum logic [1:0] { S_IDLE, S_ISSUE, S_WAIT, S_DONE } ser_state_t;
    ser_state_t state, state_n;

    logic [2:0]   step;
    logic [254:0] x_reg, xbar_reg, x2_reg, x2bar_reg, x4_reg, res_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) state <= S_IDLE;
        else       state <= state_n;
    end

    always_comb begin
        state_n = state;
        case (state)
            S_IDLE:  if (io_input_valid)                     state_n = S_ISSUE;
            S_ISSUE: if (mul_ready_i)                        state_n = S_WAIT;
            S_WAIT:  if (mul_res_valid_i)
                         state_n = (step == 3'd4) ? S_DONE : S_ISSUE;
            S_DONE:  if (io_output_ready)                    state_n = S_IDLE;
            default: state_n = S_IDLE;
        endcase
    end

    assign mul_valid_o       = (state == S_ISSUE);
    assign io_input_ready    = (state == S_IDLE);
    assign io_output_valid   = (state == S_DONE);
    assign io_output_payload = res_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            step <= '0;
            x_reg <= '0; xbar_reg <= '0; x2_reg <= '0;
            x2bar_reg <= '0; x4_reg <= '0; res_reg <= '0;
        end else begin
            if (state == S_IDLE && io_input_valid) begin
                x_reg <= io_input_payload;
                step  <= 3'd0;
            end
            if (state == S_WAIT && mul_res_valid_i) begin
                case (step)
                    3'd0: xbar_reg  <= mul_res_i;
                    3'd1: x2_reg    <= mul_res_i;
                    3'd2: x2bar_reg <= mul_res_i;
                    3'd3: x4_reg    <= mul_res_i;
                    3'd4: res_reg   <= mul_res_i;
                    default: ;
                endcase
                step <= step + 3'd1;
            end
        end
    end

    always_comb begin
        case (step)
            3'd0:    begin mul_op1_o = x_reg;     mul_op2_o = R2_MOD_N;  end
            3'd1:    begin mul_op1_o = xbar_reg;  mul_op2_o = x_reg;     end
            3'd2:    begin mul_op1_o = xbar_reg;  mul_op2_o = xbar_reg;  end
            3'd3:    begin mul_op1_o = x2bar_reg; mul_op2_o = x2_reg;    end
            default: begin mul_op1_o = x4_reg;    mul_op2_o = xbar_reg;  end
        endcase
    end

endmodule