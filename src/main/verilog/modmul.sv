`timescale 1ns/1ps

module modmul 
#(
    parameter VERSION  = 3,   // 1 = 3 mults, 2 = 1 mult, 3 = 2 mults (Middle-ground)
    parameter PIPELINE = 1,   // 0 = Blocking FSM, 1 = Pipeline Enabled
    parameter WIDTH    = 255,
    parameter MODULUS  = 255'h73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
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

generate
if (PIPELINE == 0) begin : gen_fsm
    // ====================================================================
    // NON-PIPELINED VERSION (ORIGINAL FSM)
    // ====================================================================
    typedef enum logic [2:0] {
        IDLE,
        MULTIPLICATION_INPUTS,
        INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED,
        MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED,
        REDUCE_TO_MODULUS
    } state_t;

    state_t current_state, next_state;
    logic [511:0] t;
    logic [255:0] m;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) current_state <= IDLE;
        else     current_state <= next_state;
    end

    always_comb begin
        next_state = IDLE;
        case (current_state)
            IDLE: if (op_valid_i) next_state = MULTIPLICATION_INPUTS;
            MULTIPLICATION_INPUTS: next_state = INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED;
            INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED: next_state = MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED;
            MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED: next_state = REDUCE_TO_MODULUS;
            REDUCE_TO_MODULUS: if (res_ready_i) next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    if (VERSION == 1) begin : gen_v1
        always_ff @(posedge clk, posedge rst) begin
            if (rst) begin
                t <= '0; m <= '0;
            end else begin
                if      (current_state == MULTIPLICATION_INPUTS) t <= (op1_i * op2_i);
                else if (current_state == INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED) m <= (t[255:0] * N_LINE);
                else if (current_state == MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED) t <= (t + (m * MODULUS)) >> 256;
            end
        end
    end else begin : gen_v2_v3
        // If not V1 in FSM, the behavior with 1 or 2 mults is sequentially identical
        logic [255:0] operand1, operand2;
        logic [511:0] mult_result;   
        logic [512:0] t_sum;         

        always_comb begin
            operand1 = '0; operand2 = '0;
            case (current_state)
                MULTIPLICATION_INPUTS: begin operand1 = 256'(op1_i); operand2 = 256'(op2_i); end
                INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED: begin operand1 = t[255:0]; operand2 = N_LINE; end
                MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED: begin operand1 = m; operand2 = 256'(MODULUS); end
                default: ;
            endcase
        end

        assign mult_result = operand1 * operand2;
        assign t_sum       = {1'b0, t} + {1'b0, mult_result};

        always_ff @(posedge clk, posedge rst) begin
            if (rst) begin
                t <= '0; m <= '0;
            end else begin
                case (current_state)
                    MULTIPLICATION_INPUTS: t <= mult_result;
                    INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED: m <= mult_result[255:0];
                    MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED: t <= t_sum[512:256];
                    default: ;
                endcase
            end
        end
    end

    assign res_o = (t >= MODULUS) ? (t - MODULUS) : t[WIDTH-1:0];
    assign op_ready_o  = (current_state == IDLE);
    assign res_valid_o = (current_state == REDUCE_TO_MODULUS);

end else begin : gen_pipe
    // ====================================================================
    // PIPELINED VERSION (SHIFT REGISTERS / HANDSHAKE)
    // ====================================================================
    
    // Validity control registers
    logic vld_s1, vld_s2, vld_s3, vld_s4;
    
    // Ready signals (Backpressure)
    logic rdy_s1, rdy_s2, rdy_s3, rdy_s4;

    assign rdy_s4 = res_ready_i || !vld_s4;
    assign rdy_s3 = rdy_s4      || !vld_s3;
    assign rdy_s2 = rdy_s3      || !vld_s2;

    if (VERSION == 1) begin : gen_pipe_v1
        // V1 + PIPELINE: 3 Multipliers. Accepts data EVERY 1 clock cycle.
        assign rdy_s1 = rdy_s2 || !vld_s1;
        
        logic [511:0] t_s1, t_s2; logic [255:0] m_s2; logic [256:0] t_s3; logic [WIDTH-1:0] res_s4;
        always_ff @(posedge clk) begin
            if (rdy_s1 && op_valid_i) t_s1 <= 256'(op1_i) * 256'(op2_i);
            if (rdy_s2 && vld_s1) begin t_s2 <= t_s1; m_s2 <= t_s1[255:0] * N_LINE; end
            if (rdy_s3 && vld_s2) begin logic [512:0] sum; sum = {1'b0, t_s2} + (m_s2 * MODULUS); t_s3 <= sum[512:256]; end
            if (rdy_s4 && vld_s3) res_s4 <= (t_s3 >= MODULUS) ? (t_s3 - MODULUS) : t_s3[WIDTH-1:0];
        end
        assign res_o = res_s4;

    end else if (VERSION == 2) begin : gen_pipe_v2
        // V2 + PIPELINE: 1 Shared multiplier. Accepts data EVERY 3 clock cycles.
        assign rdy_s1 = (!vld_s1 && !vld_s2 && !vld_s3); // Extreme collision protection
        
        logic [511:0] t_s1, t_s2; logic [255:0] m_s2; logic [256:0] t_s3; logic [WIDTH-1:0] res_s4;
        
        // Mux to structurally share the single multiplier
        logic [255:0] op1_mux, op2_mux; logic [511:0] mult_result;
        
        always_comb begin
            if      (vld_s2) begin op1_mux = m_s2;        op2_mux = 256'(MODULUS); end
            else if (vld_s1) begin op1_mux = t_s1[255:0]; op2_mux = N_LINE; end
            else             begin op1_mux = 256'(op1_i); op2_mux = 256'(op2_i); end
        end
        assign mult_result = op1_mux * op2_mux;

        always_ff @(posedge clk) begin
            if (rdy_s1 && op_valid_i) t_s1 <= mult_result;
            if (rdy_s2 && vld_s1) begin t_s2 <= t_s1; m_s2 <= mult_result[255:0]; end
            if (rdy_s3 && vld_s2) begin logic [512:0] sum; sum = {1'b0, t_s2} + {1'b0, mult_result}; t_s3 <= sum[512:256]; end
            if (rdy_s4 && vld_s3) res_s4 <= (t_s3 >= MODULUS) ? (t_s3 - MODULUS) : t_s3[WIDTH-1:0];
        end
        assign res_o = res_s4;

    end else if (VERSION == 3) begin : gen_pipe_v3
        // V3 + PIPELINE: 2 Multipliers. Accepts data EVERY 2 clock cycles (THE MAGIC HAPPENS HERE)
        // Ensures Mult B is not called by stages S2 and S3 simultaneously
        assign rdy_s1 = !vld_s1 && !(vld_s2 && !rdy_s3);
        
        logic [511:0] t_s1, t_s2; logic [255:0] m_s2; logic [256:0] t_s3; logic [WIDTH-1:0] res_s4;

        // Mult_A is fixed at the input
        logic [511:0] mult_A;
        assign mult_A = 256'(op1_i) * 256'(op2_i);

        // Mult_B interleaves between stage S2 and S3
        logic [255:0] op1_mux, op2_mux; logic [511:0] mult_B;
        always_comb begin
            if (vld_s2) begin // S3 has priority if filled
                op1_mux = m_s2;
                op2_mux = 256'(MODULUS);
            end else begin    // S2 uses it if S3 is empty
                op1_mux = t_s1[255:0];
                op2_mux = N_LINE;
            end
        end
        assign mult_B = op1_mux * op2_mux;

        always_ff @(posedge clk) begin
            if (rdy_s1 && op_valid_i) t_s1 <= mult_A;
            if (rdy_s2 && vld_s1) begin t_s2 <= t_s1; m_s2 <= mult_B[255:0]; end
            if (rdy_s3 && vld_s2) begin logic [512:0] sum; sum = {1'b0, t_s2} + {1'b0, mult_B}; t_s3 <= sum[512:256]; end
            if (rdy_s4 && vld_s3) res_s4 <= (t_s3 >= MODULUS) ? (t_s3 - MODULUS) : t_s3[WIDTH-1:0];
        end
        assign res_o = res_s4;
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            vld_s1 <= 1'b0; vld_s2 <= 1'b0; vld_s3 <= 1'b0; vld_s4 <= 1'b0;
        end else begin
            if (rdy_s2 || !vld_s1) vld_s1 <= op_valid_i && rdy_s1;   // <-- linha corrigida
            if (rdy_s3) vld_s2 <= vld_s1;
            if (rdy_s4) vld_s3 <= vld_s2;
            if (rdy_s4) vld_s4 <= vld_s3;
        end
    end

    assign op_ready_o  = rdy_s1;
    assign res_valid_o = vld_s4;

end
endgenerate

endmodule