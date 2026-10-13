`timescale 1ns/1ps

module modmul_tb;

localparam VERSION = 2;   // 1 = original (3 multipliers), 2 = shared multiplier
localparam WIDTH = 255;
localparam [254:0] MODULUS  = 255'h73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
localparam [254:0] R2_MOD_N = 255'h0748d9d99f59ff1105d314967254398f2b6cedcb87925c23c999e990f3f29c6d;
localparam CLK_PERIOD = 10;

logic clk;
logic rst;
logic op_valid_i;
logic op_ready_o;
logic [WIDTH-1:0] op1_i;
logic [WIDTH-1:0] op2_i;
logic res_valid_o;
logic res_ready_i;
logic [WIDTH-1:0] res_o;

modmul #(
    .VERSION(VERSION),
    .WIDTH(WIDTH),
    .MODULUS(MODULUS)
) dut (
    .clk(clk),
    .rst(rst),
    .op_valid_i(op_valid_i),
    .op_ready_o(op_ready_o),
    .op1_i(op1_i),
    .op2_i(op2_i),
    .res_valid_o(res_valid_o),
    .res_ready_i(res_ready_i),
    .res_o(res_o)
);

initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// =====================================================
// LATENCY MONITOR
// =====================================================
// Mirrors the DUT enum order (IDLE=0 ... REDUCE_TO_MODULUS=4)
localparam S_IDLE  = 0;
localparam S_MULT1 = 1;   // MULTIPLICATION_INPUTS
localparam S_MULT2 = 2;   // INVERSE_NEGATIVE_MODULUS_AND_MULT_INPUTS_TRANFORMED
localparam S_MULT3 = 3;   // MULT_BY_MODULUS_SUM_PREVIOUS_INPUTS_MULTIPLIED
localparam S_RED   = 4;   // REDUCE_TO_MODULUS

integer cycle_cnt;
integer prev_state;
integer t_start, t_m1, t_m2, t_m3, t_red;   // cycle stamps

// Samples at posedge, so it sees the state that was active
// during the cycle that just ended (DUT registers update via NBA).
always @(posedge clk) begin
    if (rst) begin
        cycle_cnt  <= 0;
        prev_state <= S_IDLE;
    end else begin
        cycle_cnt  <= cycle_cnt + 1;
        prev_state <= int'(dut.current_state);

        case (int'(dut.current_state))
            S_IDLE:  if (op_valid_i)         t_start = cycle_cnt; // op accepted
            S_MULT1:                         t_m1    = cycle_cnt; // 1st mult: op1*op2
            S_MULT2:                         t_m2    = cycle_cnt; // 2nd mult: t[255:0]*N_LINE
            S_MULT3:                         t_m3    = cycle_cnt; // 3rd mult: m*MODULUS
            S_RED:   if (prev_state != S_RED) t_red  = cycle_cnt; // res_valid first seen
            default: ;
        endcase
    end
end

task automatic report_latency(input string label);
    integer l1, l2, l3, total;
    begin
        l1    = t_m2  - t_m1;     // cycles spent in mult 1
        l2    = t_m3  - t_m2;     // cycles spent in mult 2
        l3    = t_red - t_m3;     // cycles spent in mult 3
        total = t_red - t_start;  // op accepted -> res_valid_o high

        $display("  [LATENCY] %s (VERSION=%0d)", label, VERSION);
        $display("    Mult1 (op1*op2)         : %0d cycle(s) = %0d ns", l1, l1*CLK_PERIOD);
        $display("    Mult2 (t_low*N_LINE)    : %0d cycle(s) = %0d ns", l2, l2*CLK_PERIOD);
        $display("    Mult3 (m*MODULUS + sum) : %0d cycle(s) = %0d ns", l3, l3*CLK_PERIOD);
        $display("    Total (accept -> valid) : %0d cycle(s) = %0d ns\n", total, total*CLK_PERIOD);
    end
endtask

// =====================================================
// TASK: two Montgomery passes
// =====================================================
// Inputs are driven with non-blocking assignments to avoid
// races with the DUT sampling on the same clock edge.
task run_normal_modmul(input [255:0] a, input [255:0] b, input [255:0] expected);
    logic [255:0] temp_res;
    begin
        $display("Time: %0t | Iniciando multiplicacao normal: %d * %d", $time, a, b);

        // ---------- PASSAGEM 1: a * R^2 mod N ----------
        wait(op_ready_o);
        @(posedge clk);
        op1_i      <= a;
        op2_i      <= R2_MOD_N;
        op_valid_i <= 1;
        @(posedge clk);
        op_valid_i <= 0;

        wait(res_valid_o);
        @(posedge clk);
        temp_res = res_o;            // a_bar
        res_ready_i <= 1;
        @(posedge clk);
        res_ready_i <= 0;

        $display("Time: %0t | Passagem 1 concluida (temp = a * R mod N): %h", $time, temp_res);
        report_latency("Pass 1");

        // ---------- PASSAGEM 2: temp * b mod N ----------
        wait(op_ready_o);
        @(posedge clk);
        op1_i      <= temp_res;
        op2_i      <= b;
        op_valid_i <= 1;
        @(posedge clk);
        op_valid_i <= 0;

        wait(res_valid_o);
        @(posedge clk);
        res_ready_i <= 1;
        $display("Time: %0t | Passagem 2 concluida. Resultado final: %d", $time, res_o);
        if (res_o == expected)
            $display("-> SUCESSO! Bateu com o esperado (%d)", expected);
        else
            $display("-> ERRO! Esperado: %d, Obtido: %d", expected, res_o);

        @(posedge clk);
        res_ready_i <= 0;
        report_latency("Pass 2");
    end
endtask

// =====================================================
// MAIN
// =====================================================
initial begin
    $display("========================================");
    $display("   TESTE MONTGOMERY - MODO 2 PASSAGENS");
    $display("========================================");
    $display("Time: %0t ns\n", $time);

    // 1. RESET
    rst         = 1;
    op_valid_i  = 0;
    res_ready_i = 0;
    op1_i       = 0;
    op2_i       = 0;
    @(posedge clk);
    rst <= 0;
    @(posedge clk);

    // 2. TESTES
    run_normal_modmul(255'd5,   255'd7,   255'd35);
    run_normal_modmul(255'd100, 255'd200, 255'd20000);
    run_normal_modmul(255'hFFFF, 255'hFFFF, 255'hFFFE0001);

    $display("========================================");
    $display("   TESTES CONCLUIDOS");
    $display("========================================\n");

    #(CLK_PERIOD * 5);
    $finish;
end

endmodule