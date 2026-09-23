module sbox #(
    parameter bit PARALLEL = 0
)(
    input               io_input_valid,
    output              io_input_ready,
    input               io_input_last,
    input      [254:0]  io_input_payload,
    output              io_output_valid,
    input               io_output_ready,
    //output              io_output_last,
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
    // ESTÁGIO 1: x -> x^2
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

    logic s2_ready; // Handshake do Estágio 2

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
    // ESTÁGIO 2: x^2 -> x^4
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

    logic s3_ready; // Handshake do Estágio 3

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
        // Pipeline update: Puxa tanto o x^2 quanto o x original do Estágio 1
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
    // ESTÁGIO 3: x^4 * x -> x^5
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
        // Pipeline update: Recebe o x^4 e o x original que viajou pelo Estágio 2
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
    // SAÍDAS DO MÓDULO TOP
    // ==========================================
    
    assign io_output_valid = (s3_state == DONE);
    assign io_output_payload = s3_x5_out;

end else begin: SERIAL_IMPLEMENTATION

    // ==========================================
    // IMPLEMENTAÇÃO SERIAL (1 MULTIPLICADOR)
    // ==========================================


    // Using the 2-pass Montgomery multiplication approach
    // Pass 1: temp = a * R^2 mod N
    // Pass 2: result = temp * b mod N
    // Total steps for x^5 = 3 logical multiplications * 2 passes = 6 steps
    localparam integer NUM_MULTS = 6; 
    localparam [254:0] R2_MOD_N = 255'h0748d9d99f59ff1105d314967254398f2b6cedcb87925c23c999e990f3f29c6d;

    logic         mul_valid;
    logic         mul_ready;
    logic         mult_result_valid;
    logic [254:0] mul_result;

    logic [254:0] mul_op1;
    logic [254:0] mul_op2;

    modmul #() mod_multiplier (
        .clk(clk),
        .rst(reset),
        .op_valid_i(mul_valid),
        .op_ready_o(mul_ready),
        .op1_i(mul_op1),
        .op2_i(mul_op2),
        .res_valid_o(mult_result_valid),
        .res_ready_i(1'b1),
        .res_o(mul_result)
    );

    typedef enum logic[1:0]{
        IDLE           = 2'b01,
        MULTIPLY       = 2'b10
    } state_e;

    state_e current_state, next_state;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    logic [31:0] cont_mult_sum_accum;

    always_comb begin
        next_state = IDLE;
        case (current_state)
            IDLE: begin
                if (io_input_valid) begin
                    next_state = MULTIPLY;
                end
                else begin
                    next_state = IDLE;
                end
            end
            MULTIPLY: begin
                if (cont_mult_sum_accum == NUM_MULTS) begin
                    next_state = IDLE;
                end
                else begin
                    next_state = MULTIPLY;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    logic mul_valid_reg;

    // multiplier control signals
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            mul_valid_reg <= 1'b0;
        end
        else begin
            if (current_state == MULTIPLY && cont_mult_sum_accum < NUM_MULTS) begin
                mul_valid_reg <= 1'b1;
            end
            else begin
                mul_valid_reg <= 1'b0;
            end
        end
    end

    logic mult_result_valid_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            mult_result_valid_reg <= 1'b0;
        end
        else begin
            if (current_state == MULTIPLY) begin
                mult_result_valid_reg <= mult_result_valid;
            end
            else begin
                mult_result_valid_reg <= 1'b0;
            end
        end
    end

    // Added mul_ready and boundary check to ensure stable handshakes
    assign mul_valid = mul_valid_reg & ~mult_result_valid & ~mult_result_valid_reg & mul_ready & (cont_mult_sum_accum < NUM_MULTS);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            cont_mult_sum_accum <= 0;
        end else begin
            if(current_state == IDLE) begin
                cont_mult_sum_accum <= 0;
            end else begin
                if (current_state == MULTIPLY) begin
                    if(mult_result_valid) begin
                        cont_mult_sum_accum <= cont_mult_sum_accum + 1;
                    end
                end
            end
        end
    end

    logic io_input_ready_reg, io_output_valid_reg;

    always_comb begin
        io_input_ready_reg = 1'b0;
        io_output_valid_reg = 1'b0;

        case (current_state)
            IDLE: begin
                io_input_ready_reg = 1'b1;
            end
            MULTIPLY: begin
                if(cont_mult_sum_accum == NUM_MULTS) begin
                    io_output_valid_reg = 1'b1;
                end
            end
        endcase
    end

    assign io_input_ready = io_input_ready_reg;
    assign io_output_valid = io_output_valid_reg;

    logic [254:0] input_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            input_reg <= 255'b0;
        end else begin
            if (current_state == IDLE && io_input_valid) begin
                input_reg <= io_input_payload;
            end
        end
    end

    logic [254:0] temp_reg;
    logic [254:0] result_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            temp_reg <= 255'b0;
            result_reg <= 255'b1;
        end else begin
            if (current_state == IDLE) begin
                result_reg <= 255'b1;
            end else if (current_state == MULTIPLY) begin
                if (mult_result_valid) begin
                    if (cont_mult_sum_accum[0] == 1'b0) begin
                        // Even steps (0, 2, 4): Store output of Pass 1 (a * R^2)
                        temp_reg <= mul_result;
                    end else begin
                        // Odd steps (1, 3, 5): Store final multiplication result
                        result_reg <= mul_result;
                    end
                end
            end
        end
    end

    // Operand mux for the 3-step addition chain broken into 6 passes:
    //   Logical step 0: x   * x   -> x^2 (Passes 0 and 1)
    //   Logical step 1: x^2 * x^2 -> x^4 (Passes 2 and 3)
    //   Logical step 2: x^4 * x   -> x^5 (Passes 4 and 5)
    always_comb begin
        case (cont_mult_sum_accum)
            // MULT 1: x * x
            32'd0: begin // Pass 1: x * R^2 mod N
                mul_op1 = input_reg;
                mul_op2 = R2_MOD_N;
            end
            32'd1: begin // Pass 2: temp * x mod N
                mul_op1 = temp_reg;
                mul_op2 = input_reg;
            end
            
            // MULT 2: x^2 * x^2
            32'd2: begin // Pass 1: x^2 * R^2 mod N
                mul_op1 = result_reg;
                mul_op2 = R2_MOD_N;
            end
            32'd3: begin // Pass 2: temp * x^2 mod N
                mul_op1 = temp_reg;
                mul_op2 = result_reg;
            end
            
            // MULT 3: x^4 * x
            32'd4: begin // Pass 1: x^4 * R^2 mod N
                mul_op1 = result_reg;
                mul_op2 = R2_MOD_N;
            end
            32'd5: begin // Pass 2: temp * x mod N
                mul_op1 = temp_reg;
                mul_op2 = input_reg;
            end
            default: begin
                mul_op1 = input_reg;
                mul_op2 = R2_MOD_N;
            end
        endcase
    end

    assign io_output_payload = result_reg;

end

endmodule