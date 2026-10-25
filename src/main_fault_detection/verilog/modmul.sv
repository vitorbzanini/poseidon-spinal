`timescale 1ns/1ps

// ============================================================================
// modmul_pipe_add : pipelined adder  sum = a + b + cin
//   The W-bit carry chain is cut into W/S slices of S bits. Each slice is
//   computed in its own clock cycle and the carry between slices is
//   registered, so no carry chain is longer than S bits (S=128 -> ~3 ns).
//   Latency : W/S clock cycles (inputs sampled at the first edge).
//   sb_i/sb_o : sideband bus delayed by exactly the same latency.
// ============================================================================
module modmul_pipe_add #(
    parameter W   = 512,
    parameter S   = 128,
    parameter SBW = 1
)(
    input  logic           clk,
    input  logic [W-1:0]   a,
    input  logic [W-1:0]   b,
    input  logic           cin,
    input  logic [SBW-1:0] sb_i,
    output logic [W-1:0]   sum,
    output logic           cout,
    output logic [SBW-1:0] sb_o
);
    localparam N = W / S;

    logic [W-1:0]   a_r  [0:N-1];
    logic [W-1:0]   b_r  [0:N-1];
    logic [W-1:0]   s_r  [0:N-1];
    logic           c_r  [0:N-1];
    logic [SBW-1:0] sb_r [0:N-1];

    genvar g;
    generate
        for (g = 0; g < N; g++) begin : stg
            logic [W-1:0]   a_in, b_in, s_in, s_nxt;
            logic           c_in;
            logic [SBW-1:0] sb_in;
            logic [S:0]     part;

            if (g == 0) begin : first
                assign a_in  = a;
                assign b_in  = b;
                assign s_in  = '0;
                assign c_in  = cin;
                assign sb_in = sb_i;
            end else begin : rest
                assign a_in  = a_r[g-1];
                assign b_in  = b_r[g-1];
                assign s_in  = s_r[g-1];
                assign c_in  = c_r[g-1];
                assign sb_in = sb_r[g-1];
            end

            assign part = {1'b0, a_in[g*S +: S]} + {1'b0, b_in[g*S +: S]} + {{S{1'b0}}, c_in};

            always_comb begin
                s_nxt = s_in;
                s_nxt[g*S +: S] = part[S-1:0];
            end

            always_ff @(posedge clk) begin
                a_r[g]  <= a_in;
                b_r[g]  <= b_in;
                s_r[g]  <= s_nxt;
                c_r[g]  <= part[S];
                sb_r[g] <= sb_in;
            end
        end
    endgenerate

    assign sum  = s_r[N-1];
    assign cout = c_r[N-1];
    assign sb_o = sb_r[N-1];
endmodule


// ============================================================================
// modmul_pipe_mult : fully pipelined 256x256 multiplier (fixed latency)
//   * operands cut into 16 limbs of 16 bits -> 16x16 tiles, 1 DSP each
//   * column sums (limb-aligned) in a 2-level adder tree
//   * 2 small carry-normalisation rounds, then one sliced pipelined add
//   LOWONLY=1 : only the low 256 bits of the product are produced
//               (only tiles with i+j<16 are built -> 136 DSPs instead of 256)
//   Latency : 6 + PW/S cycles   (PW = 512 -> 10 cycles, PW = 256 -> 8 cycles)
//   Throughput : 1 operation per cycle.
//   sb_i/sb_o : sideband bus delayed by exactly the same latency.
// ============================================================================
module modmul_pipe_mult #(
    parameter LOWONLY = 0,
    parameter SBW     = 1,
    parameter S       = 128,
    parameter PW      = LOWONLY ? 256 : 512
)(
    input  logic           clk,
    input  logic [255:0]   a,
    input  logic [255:0]   b,
    input  logic [SBW-1:0] sb_i,
    output logic [PW-1:0]  p,
    output logic [SBW-1:0] sb_o
);
    localparam NC = LOWONLY ? 16 : 32;     // number of 16-bit result limbs

    // ---- stage 0 : input registers ------------------------------------------
    logic [15:0]    ar [0:15];
    logic [15:0]    br [0:15];
    logic [SBW-1:0] sb0, sb1, sb2, sb3, sb4, sb5;

    always_ff @(posedge clk) begin
        for (int i = 0; i < 16; i++) begin
            ar[i] <= a[16*i +: 16];
            br[i] <= b[16*i +: 16];
        end
        sb0 <= sb_i;
        sb1 <= sb0;
        sb2 <= sb1;
        sb3 <= sb2;
        sb4 <= sb3;
        sb5 <= sb4;
    end

    // ---- stage 1 : 16x16 tile products (DSP48, registered) --------------------
    logic [31:0] pr [0:15][0:15];
    genvar gi, gj, k, gg, q;
    generate
        for (gi = 0; gi < 16; gi++) begin : rowi
            for (gj = 0; gj < 16; gj++) begin : colj
                if (gi + gj < NC) begin : used
                    always_ff @(posedge clk) pr[gi][gj] <= ar[gi] * br[gj];
                end
            end
        end
    endgenerate

    // ---- stage 2/3 : column sums  C_k = sum_{i+j=k} pr[i][j]  (36 bits) --------
    logic [35:0] cc [0:NC-1];
    generate
        for (k = 0; k < NC; k++) begin : col
            localparam LO = (k > 15) ? (k - 15) : 0;
            localparam HI = (k < 15) ? k : 15;
            logic [35:0] s1 [0:3];
            for (gg = 0; gg < 4; gg++) begin : grp
                logic [35:0] term [0:3];
                for (q = 0; q < 4; q++) begin : t
                    localparam I = LO + 4*gg + q;
                    if (I <= HI) begin : y
                        assign term[q] = {4'd0, pr[I][k-I]};
                    end else begin : n
                        assign term[q] = 36'd0;
                    end
                end
                always_ff @(posedge clk) s1[gg] <= term[0] + term[1] + term[2] + term[3];
            end
            always_ff @(posedge clk) cc[k] <= s1[0] + s1[1] + s1[2] + s1[3];
        end
    endgenerate

    // ---- stage 4/5 : carry normalisation rounds --------------------------------
    //   D_k = lo16(C_k) + hi20(C_{k-1})      (<= 21 bits)
    //   E_k = lo16(D_k) + hi5 (D_{k-1})      (<= 17 bits)
    logic [20:0] dd [0:NC-1];
    logic [16:0] ee [0:NC-1];
    generate
        for (k = 0; k < NC; k++) begin : norm
            if (k == 0) begin : k0
                always_ff @(posedge clk) begin
                    dd[k] <= {5'd0, cc[k][15:0]};
                    ee[k] <= {1'b0, dd[k][15:0]};
                end
            end else begin : kn
                always_ff @(posedge clk) begin
                    dd[k] <= {5'd0, cc[k][15:0]} + {1'b0, cc[k-1][35:16]};
                    ee[k] <= {1'b0, dd[k][15:0]} + {12'd0, dd[k-1][20:16]};
                end
            end
        end
    endgenerate

    // ---- final : L + H  (sliced pipelined adder) ---------------------------------
    logic [PW-1:0] lv, hv;
    generate
        for (k = 0; k < NC; k++) begin : asm
            assign lv[16*k +: 16] = ee[k][15:0];
            if (k == 0) begin : h0
                assign hv[16*k +: 16] = 16'd0;
            end else begin : hn
                assign hv[16*k +: 16] = {15'd0, ee[k-1][16]};
            end
        end
    endgenerate

    modmul_pipe_add #(.W(PW), .S(S), .SBW(SBW)) u_add (
        .clk (clk),
        .a   (lv),
        .b   (hv),
        .cin (1'b0),
        .sb_i(sb5),
        .sum (p),
        .cout(),
        .sb_o(sb_o)
    );
endmodule


// ============================================================================
// modmul
// ============================================================================
module modmul 
#(
    parameter VERSION  = 4,   // 1 = 3 mults, 2 = 1 mult, 3 = 2 mults (Middle-ground)
                              // 4 = FULLY PIPELINED, timing-optimised (100 MHz target)
    parameter PIPELINE = 1,   // 0 = Blocking FSM, 1 = Pipeline Enabled (VERSION 4 is always pipelined)
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
if (VERSION == 4) begin : gen_pipe_v4
    // ====================================================================
    // V4: FULLY PIPELINED, 3 separate multipliers, 1 operation per cycle.
    //
    //   S1  T  = op1 * op2                      (256x256 -> 512, 10 cycles)
    //   S2  m  = (T[255:0] * N_LINE) mod 2^256  (low half only,   8 cycles)
    //   S3  P  = m * MODULUS                    (256x256 -> 512, 10 cycles)
    //   S4  t3 = (T + P) >> 256                 (sliced adder,    4 cycles)
    //   S5  d  = t3 - MODULUS                   (sliced adder,    3 cycles)
    //   S6  res = (t3 >= MODULUS) ? d : t3      (                 1 cycle )
    //   Total latency = 36 cycles. No combinational path is longer than a
    //   16x16 DSP tile, a 4-input 36-bit add or a 128-bit carry chain.
    //
    //   Back-pressure (res_ready_i) is handled with credits + an output FIFO,
    //   because a fixed-latency pipeline cannot be stalled in the middle.
    // ====================================================================
    localparam SL      = 128;                                  // adder slice width
    localparam LAT     = (6 + 512/SL) + (6 + 256/SL) + (6 + 512/SL) + (512/SL) + (384/SL) + 1;
    localparam FIFO_AW = 6;
    localparam CREDITS = LAT + 8;                              // must be < 2**FIFO_AW
    localparam [FIFO_AW:0] CREDITS_C = CREDITS;

    // ---------------- control: valid shift register + credits + FIFO -----------
    logic [LAT-1:0]     vsr;
    logic [FIFO_AW-1:0] wr_ptr;
    // rd_ptr enderecando a RAM distribuida de 255 bits (fanout ~258): pede replicacao
    (* max_fanout = 16 *) logic [FIFO_AW-1:0] rd_ptr;
    logic [FIFO_AW:0]   inflight;
    logic               accept, push, pop;
    logic [WIDTH-1:0]   res_f;

    assign op_ready_o = (inflight < CREDITS_C);
    assign accept     = op_valid_i && op_ready_o;
    assign push       = vsr[LAT-1];
    assign res_valid_o = (wr_ptr != rd_ptr);
    assign pop        = res_valid_o && res_ready_i;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            vsr      <= '0;
            wr_ptr   <= '0;
            rd_ptr   <= '0;
            inflight <= '0;
        end else begin
            vsr      <= {vsr[LAT-2:0], accept};
            if (push) wr_ptr <= wr_ptr + 1'b1;
            if (pop)  rd_ptr <= rd_ptr + 1'b1;
            inflight <= inflight + {{FIFO_AW{1'b0}}, accept} - {{FIFO_AW{1'b0}}, pop};
        end
    end

    (* ram_style = "distributed" *) logic [WIDTH-1:0] fifo_mem [0:(1<<FIFO_AW)-1];
    always_ff @(posedge clk) if (push) fifo_mem[wr_ptr] <= res_f;
    assign res_o = fifo_mem[rd_ptr];

    // ---------------- data path -------------------------------------------------
    logic [255:0] opa, opb;
    assign opa = 256'(op1_i);
    assign opb = 256'(op2_i);

    // S1: T = op1 * op2
    logic [511:0] t_a, p_unused;
    logic [0:0]   sb_unused_a;
    modmul_pipe_mult #(.LOWONLY(0), .SBW(1), .S(SL)) u_mult_a (
        .clk(clk), .a(opa), .b(opb), .sb_i(1'b0), .p(t_a), .sb_o(sb_unused_a)
    );

    // S2: m = low256(T_low * N_LINE); T travels along as sideband
    logic [255:0] m_b;
    logic [511:0] t_b;
    modmul_pipe_mult #(.LOWONLY(1), .SBW(512), .S(SL)) u_mult_b (
        .clk(clk), .a(t_a[255:0]), .b(N_LINE), .sb_i(t_a), .p(m_b), .sb_o(t_b)
    );

    // S3: P = m * MODULUS; T keeps travelling
    logic [511:0] p_c, t_c;
    modmul_pipe_mult #(.LOWONLY(0), .SBW(512), .S(SL)) u_mult_c (
        .clk(clk), .a(m_b), .b(256'(MODULUS)), .sb_i(t_b), .p(p_c), .sb_o(t_c)
    );

    // S4: sum = T + P ; t3 = sum >> 256  (257 bits, including the carry out)
    logic [511:0] sum_d;
    logic         cout_d;
    logic [0:0]   sb_unused_d;
    modmul_pipe_add #(.W(512), .S(SL), .SBW(1)) u_add_t (
        .clk(clk), .a(t_c), .b(p_c), .cin(1'b0), .sb_i(1'b0),
        .sum(sum_d), .cout(cout_d), .sb_o(sb_unused_d)
    );
    logic [256:0] t3;
    assign t3 = {cout_d, sum_d[511:256]};

    // S5: d = t3 - MODULUS  (two's complement in 384 bits; MSB = borrow)
    logic [383:0]       diff_e;
    logic               cout_e;
    logic [WIDTH-1:0]   t3_e;
    modmul_pipe_add #(.W(384), .S(SL), .SBW(WIDTH)) u_sub (
        .clk(clk),
        .a({127'd0, t3}),
        .b(~(384'(MODULUS))),
        .cin(1'b1),
        .sb_i(t3[WIDTH-1:0]),
        .sum(diff_e), .cout(cout_e), .sb_o(t3_e)
    );

    // S6: select
    always_ff @(posedge clk) res_f <= diff_e[383] ? t3_e : diff_e[WIDTH-1:0];

end else if (PIPELINE == 0) begin : gen_fsm
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

    // Captura os operandos no handshake (IDLE && op_valid_i).
    // Sem isso, a FSM le op1_i/op2_i um ciclo DEPOIS do handshake,
    // quando quem instanciou o modmul ja pode ter trocado os operandos.
    logic [WIDTH-1:0] op1_q, op2_q;
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            op1_q <= '0; op2_q <= '0;
        end else if (current_state == IDLE && op_valid_i) begin
            op1_q <= op1_i; op2_q <= op2_i;
        end
    end

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
                if      (current_state == MULTIPLICATION_INPUTS) t <= (op1_q * op2_q);
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
                MULTIPLICATION_INPUTS: begin operand1 = 256'(op1_q); operand2 = 256'(op2_q); end
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