`timescale 1ns/1ps

module sbox #(
    parameter bit PARALLEL = 0
)(
    input               io_input_valid,
    output              io_input_ready,
    input               io_input_last,
    input      [254:0]  io_input_payload,
    output              io_output_valid,
    input               io_output_ready,
    output     [254:0]  io_output_payload,
    input               clk,
    input               reset
);

if (PARALLEL) begin: PARALLEL_IMPLEMENTATION

    localparam [254:0] R2_MOD_N = 255'h0748d9d99f59ff1105d314967254398f2b6cedcb87925c23c999e990f3f29c6d;

    typedef enum logic [2:0] {
        IDLE    = 3'd0,
        P1      = 3'd1, // Pass 1: operand * R^2
        P1_WAIT = 3'd2,
        P2      = 3'd3, // Pass 2: temp * operand
        P2_WAIT = 3'd4,
        DONE    = 3'd5  // Wait for next stage to be ready
    } pipe_state_t;

    // ==========================================
    // STAGE 1: x -> x^2
    // ==========================================
    pipe_state_t s1_state, s1_next;
    logic [254:0] s1_x_in_reg, s1_temp_reg, s1_x2_out;
    logic         m1_valid, m1_ready, m1_res_valid;
    logic [254:0] m1_op1, m1_op2, m1_res;

    modmul #() mult_1 (
        .clk(clk), .rst(reset),
        .op_valid_i(m1_valid), .op_ready_o(m1_ready),
        .op1_i(m1_op1), .op2_i(m1_op2),
        .res_valid_o(m1_res_valid), .res_ready_i(1'b1), .res_o(m1_res)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset) s1_state <= IDLE;
        else       s1_state <= s1_next;
    end

    logic s2_ready; // Stage 2 Handshake

    always_comb begin
        s1_next = s1_state;
        case (s1_state)
            IDLE:    if (io_input_valid) s1_next = P1;
            P1:      if (m1_ready)       s1_next = P1_WAIT;
            P1_WAIT: if (m1_res_valid)   s1_next = P2;
            P2:      if (m1_ready)       s1_next = P2_WAIT;
            P2_WAIT: if (m1_res_valid)   s1_next = DONE;
            DONE:    if (s2_ready)       s1_next = IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (s1_state == IDLE && io_input_valid) s1_x_in_reg <= io_input_payload;
        if (s1_state == P1_WAIT && m1_res_valid) s1_temp_reg <= m1_res;
        if (s1_state == P2_WAIT && m1_res_valid) s1_x2_out <= m1_res;
    end

    assign m1_valid = (s1_state == P1) || (s1_state == P2);
    assign m1_op1   = (s1_state == P1 || s1_state == P1_WAIT) ? s1_x_in_reg : s1_temp_reg;
    assign m1_op2   = (s1_state == P1 || s1_state == P1_WAIT) ? R2_MOD_N : s1_x_in_reg;

    assign io_input_ready = (s1_state == IDLE);

    // ==========================================
    // STAGE 2: x^2 -> x^4
    // ==========================================
    pipe_state_t s2_state, s2_next;
    logic [254:0] s2_x_pass_reg, s2_x2_in_reg, s2_temp_reg, s2_x4_out;
    logic         m2_valid, m2_ready, m2_res_valid;
    logic [254:0] m2_op1, m2_op2, m2_res;

    modmul #() mult_2 (
        .clk(clk), .rst(reset),
        .op_valid_i(m2_valid), .op_ready_o(m2_ready),
        .op1_i(m2_op1), .op2_i(m2_op2),
        .res_valid_o(m2_res_valid), .res_ready_i(1'b1), .res_o(m2_res)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset) s2_state <= IDLE;
        else       s2_state <= s2_next;
    end

    logic s3_ready; // Stage 3 Handshake

    always_comb begin
        s2_next = s2_state;
        case (s2_state)
            IDLE:    if (s1_state == DONE) s2_next = P1;
            P1:      if (m2_ready)         s2_next = P1_WAIT;
            P1_WAIT: if (m2_res_valid)     s2_next = P2;
            P2:      if (m2_ready)         s2_next = P2_WAIT;
            P2_WAIT: if (m2_res_valid)     s2_next = DONE;
            DONE:    if (s3_ready)         s2_next = IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        // Pipeline update: Forward both x^2 and the original x from Stage 1
        if (s2_state == IDLE && s1_state == DONE) begin
            s2_x2_in_reg  <= s1_x2_out;
            s2_x_pass_reg <= s1_x_in_reg; 
        end
        if (s2_state == P1_WAIT && m2_res_valid) s2_temp_reg <= m2_res;
        if (s2_state == P2_WAIT && m2_res_valid) s2_x4_out <= m2_res;
    end

    assign m2_valid = (s2_state == P1) || (s2_state == P2);
    assign m2_op1   = (s2_state == P1 || s2_state == P1_WAIT) ? s2_x2_in_reg : s2_temp_reg;
    assign m2_op2   = (s2_state == P1 || s2_state == P1_WAIT) ? R2_MOD_N : s2_x2_in_reg;

    assign s2_ready = (s2_state == IDLE);

    // ==========================================
    // STAGE 3: x^4 * x -> x^5
    // ==========================================
    pipe_state_t s3_state, s3_next;
    logic [254:0] s3_x_in_reg, s3_x4_in_reg, s3_temp_reg, s3_x5_out;
    logic         m3_valid, m3_ready, m3_res_valid;
    logic [254:0] m3_op1, m3_op2, m3_res;

    modmul #() mult_3 (
        .clk(clk), .rst(reset),
        .op_valid_i(m3_valid), .op_ready_o(m3_ready),
        .op1_i(m3_op1), .op2_i(m3_op2),
        .res_valid_o(m3_res_valid), .res_ready_i(1'b1), .res_o(m3_res)
    );

    always_ff @(posedge clk or posedge reset) begin
        if (reset) s3_state <= IDLE;
        else       s3_state <= s3_next;
    end

    always_comb begin
        s3_next = s3_state;
        case (s3_state)
            IDLE:    if (s2_state == DONE) s3_next = P1;
            P1:      if (m3_ready)         s3_next = P1_WAIT;
            P1_WAIT: if (m3_res_valid)     s3_next = P2;
            P2:      if (m3_ready)         s3_next = P2_WAIT;
            P2_WAIT: if (m3_res_valid)     s3_next = DONE;
            DONE:    if (io_output_ready)  s3_next = IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        // Pipeline update: Forward x^4 and the original x traveling through Stage 2
        if (s3_state == IDLE && s2_state == DONE) begin
            s3_x4_in_reg <= s2_x4_out;
            s3_x_in_reg  <= s2_x_pass_reg;
        end
        if (s3_state == P1_WAIT && m3_res_valid) s3_temp_reg <= m3_res;
        if (s3_state == P2_WAIT && m3_res_valid) s3_x5_out <= m3_res;
    end

    assign m3_valid = (s3_state == P1) || (s3_state == P2);
    assign m3_op1   = (s3_state == P1 || s3_state == P1_WAIT) ? s3_x4_in_reg : s3_temp_reg;
    assign m3_op2   = (s3_state == P1 || s3_state == P1_WAIT) ? R2_MOD_N : s3_x_in_reg;

    assign s3_ready = (s3_state == IDLE);

    // ==========================================
    // TOP MODULE OUTPUTS
    // ==========================================
    assign io_output_valid = (s3_state == DONE);
    assign io_output_payload = s3_x5_out;

end else begin: SERIAL_IMPLEMENTATION

    localparam [254:0] R2_MOD_N = 255'h0748d9d99f59ff1105d314967254398f2b6cedcb87925c23c999e990f3f29c6d;

    typedef enum logic [1:0] { S_IDLE, S_ISSUE, S_WAIT, S_DONE } ser_state_t;
    ser_state_t state, state_n;

    logic [2:0]   step;
    logic [254:0] x_reg, xbar_reg, x2_reg, x2bar_reg, x4_reg, res_reg;

    logic         mul_valid, mul_ready, mul_res_valid;
    logic [254:0] mul_op1, mul_op2, mul_res;

    modmul mod_multiplier (
        .clk(clk), .rst(reset),
        .op_valid_i(mul_valid), .op_ready_o(mul_ready),
        .op1_i(mul_op1), .op2_i(mul_op2),
        .res_valid_o(mul_res_valid), .res_ready_i(1'b1), .res_o(mul_res)
    );

    // FSM
    always_ff @(posedge clk or posedge reset) begin
        if (reset) state <= S_IDLE;
        else       state <= state_n;
    end

    always_comb begin
        state_n = state;
        case (state)
            S_IDLE:  if (io_input_valid)                     state_n = S_ISSUE;
            S_ISSUE: if (mul_ready)                          state_n = S_WAIT;   // aceita no mesmo ciclo
            S_WAIT:  if (mul_res_valid)
                         state_n = (step == 3'd4) ? S_DONE : S_ISSUE;
            S_DONE:  if (io_output_ready)                    state_n = S_IDLE;
            default: state_n = S_IDLE;
        endcase
    end

    assign mul_valid       = (state == S_ISSUE);
    assign io_input_ready  = (state == S_IDLE);
    assign io_output_valid = (state == S_DONE);
    assign io_output_payload = res_reg;

    // Datapath
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
            if (state == S_WAIT && mul_res_valid) begin
                case (step)
                    3'd0: xbar_reg  <= mul_res;
                    3'd1: x2_reg    <= mul_res;
                    3'd2: x2bar_reg <= mul_res;
                    3'd3: x4_reg    <= mul_res;
                    3'd4: res_reg   <= mul_res;
                    default: ;
                endcase
                step <= step + 3'd1;
            end
        end
    end

    // Operandos por passo
    always_comb begin
        case (step)
            3'd0:    begin mul_op1 = x_reg;     mul_op2 = R2_MOD_N;  end
            3'd1:    begin mul_op1 = xbar_reg;  mul_op2 = x_reg;     end
            3'd2:    begin mul_op1 = xbar_reg;  mul_op2 = xbar_reg;  end
            3'd3:    begin mul_op1 = x2bar_reg; mul_op2 = x2_reg;    end
            default: begin mul_op1 = x4_reg;    mul_op2 = xbar_reg;  end
        endcase
    end

end
endmodule