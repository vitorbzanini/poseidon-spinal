module PoseidonTopLevel (
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

endmodule