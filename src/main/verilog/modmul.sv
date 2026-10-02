`timescale 1ns/1ps

module modmul 
#(
    parameter VERSION = 1,   // 1 = original (3 multipliers), 2 = shared single multiplier
    parameter WIDTH   = 255,
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

// ---------------- FSM (common to both versions) ----------------
always_ff @(posedge clk, posedge rst) begin
    if (rst) current_state <= IDLE;
    else     current_state <= next_state;
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
        default: next_state = IDLE;
    endcase
end

// ---------------- Datapath registers (common) ----------------
logic [511:0] t;
logic [255:0] m;

// ---------------- Version selection ----------------
generate
if (VERSION == 1) begin : gen_v1
    // Original: three independent multipliers, one per state
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            t <= '0;
        end else begin
            if      (current_state == MULTIPLICATION_INPUTS)
                t <= (op1_i * op2_i);
            else if (current_state == INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED)
                m <= (t[255:0] * N_LINE);
            else if (current_state == MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED)
                t <= (t + (m * MODULUS)) >> 256;
        end
    end

end else if (VERSION == 2) begin : gen_v2
    // Shared: one multiplier, operands muxed by state
    logic [255:0] operand1, operand2;
    logic [511:0] mult_result;   // 256x256 -> 512 bits
    logic [512:0] t_sum;         // extra carry bit for safety

    always_comb begin
        operand1 = '0;
        operand2 = '0;
        case (current_state)
            MULTIPLICATION_INPUTS: begin
                operand1 = 256'(op1_i);
                operand2 = 256'(op2_i);
            end
            INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED: begin
                operand1 = t[255:0];
                operand2 = N_LINE;
            end
            MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED: begin
                operand1 = m;
                operand2 = 256'(MODULUS);
            end
            default: ;
        endcase
    end

    assign mult_result = operand1 * operand2;
    assign t_sum       = {1'b0, t} + {1'b0, mult_result};

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            t <= '0;
            m <= '0;
        end else begin
            case (current_state)
                MULTIPLICATION_INPUTS:
                    t <= mult_result;
                INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED:
                    m <= mult_result[255:0];
                MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED:
                    t <= t_sum[512:256];
                default: ;
            endcase
        end
    end

end else begin : gen_invalid
    initial $error("modmul: VERSION must be 1 or 2, got %0d", VERSION);
end
endgenerate

// ---------------- Output (common) ----------------
assign res_o = (t >= MODULUS) ? (t - MODULUS) : t;

assign op_ready_o  = (current_state == IDLE);
assign res_valid_o = (current_state == REDUCE_TO_MODULUS);

endmodule