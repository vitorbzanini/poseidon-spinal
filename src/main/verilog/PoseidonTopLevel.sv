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

localparam integer NUM_MULTS = 3; // x^5 = ((x*x) squared) * x -> 3 multiplications

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
        if (current_state == MULTIPLY) begin
            mul_valid_reg <= 1'b1;
        end
        else begin
            mul_valid_reg <= 1'b0;
        end
    end
end

assign mul_valid = mul_valid_reg & ~mult_result_valid & ~mult_result_valid_reg;

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

// Latch x itself -- needed again at step 2 (x^4 * x)
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

// Running power: x^2 after step0, x^4 after step1, x^5 after step2
logic [254:0] result_reg;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        result_reg <= 255'b1;
    end else begin
        if (current_state == MULTIPLY) begin
            if (mult_result_valid) begin
                result_reg <= mul_result;
            end
        end else begin
            result_reg <= 255'b1;
        end
    end
end

// Operand mux for the 3-step addition chain:
//   step 0: x   * x   -> x^2
//   step 1: x^2 * x^2 -> x^4
//   step 2: x^4 * x   -> x^5
always_comb begin
    case (cont_mult_sum_accum)
        32'd0: begin
            mul_op1 = input_reg;
            mul_op2 = input_reg;
        end
        32'd1: begin
            mul_op1 = result_reg;
            mul_op2 = result_reg;
        end
        default: begin // step 2
            mul_op1 = result_reg;
            mul_op2 = input_reg;
        end
    endcase
end

assign io_output_payload = result_reg;

endmodule