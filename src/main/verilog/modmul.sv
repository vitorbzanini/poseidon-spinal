`timescale 1ns/1ps

module modmul 
#(
    parameter WIDTH = 255,
    parameter MODULUS = 255'h73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
)(
    input  clk,
    input  rst,

    input   op_valid_i,
    output  op_ready_o,

    input  [WIDTH-1:0] op1_i,
    input  [WIDTH-1:0] op2_i,

    output  res_valid_o,
    input   res_ready_i,
    output  [WIDTH-1:0] res_o
);

parameter logic [255:0] N_LINE = 256'h3d443ab0d7bf2839181b2c170004ec0653ba5bfffffe5bfdfffffffeffffffff;

typedef enum logic [2:0] {
    IDLE,
    MULTIPLICATION_INPUTS,
    INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED,
    MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED,
    REDUCE_TO_MODULUS
} state_t;

state_t current_state, next_state;

always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
        current_state <= IDLE;
    end else begin
        current_state <= next_state;
    end
end

always_comb begin
    next_state = IDLE;
    case (current_state)
        IDLE: begin
            if (op_valid_i) next_state = MULTIPLICATION_INPUTS;
        end
        MULTIPLICATION_INPUTS: begin
            next_state = INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED;
        end
        INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED: begin
            next_state = MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED;
        end
        MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED: begin
            next_state = REDUCE_TO_MODULUS;
        end
        REDUCE_TO_MODULUS: begin
            if (res_ready_i) next_state = IDLE;
        end
    endcase
end

logic [511:0] t;

logic [255:0] m;

always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
        t <= '0;
    end else begin
        if(current_state == MULTIPLICATION_INPUTS) t <= (op1_i * op2_i);
        else if(current_state == INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED) m <= (t[255:0] * N_LINE);
        else if(current_state == MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED) t <= (t + (m * MODULUS)) >> 256;
    end
end

assign res_o = (t >= MODULUS) ? (t - MODULUS) : t;


assign op_ready_o  = (current_state == IDLE);
assign res_valid_o = (current_state == REDUCE_TO_MODULUS);

endmodule