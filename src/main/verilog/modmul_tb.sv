`timescale 1ns/1ps

module modmul_tb;

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

    // Task que executa as duas passagens pelo multiplicador de Montgomery
    task run_normal_modmul(input [255:0] a, input [255:0] b, input [255:0] expected);
        logic [255:0] temp_res;
        
        $display("Time: %0t | Iniciando multiplicacao normal: %d * %d", $time, a, b);

        // ==========================================
        // PASSAGEM 1: a * R^2 mod N
        // ==========================================
        wait(op_ready_o);
        @(posedge clk);
        op1_i = a;
        op2_i = R2_MOD_N;
        op_valid_i = 1;
        
        @(posedge clk);
        op_valid_i = 0;

        wait(res_valid_o);
        @(posedge clk);
        temp_res = res_o; // Salva o a_bar
        res_ready_i = 1;
        
        @(posedge clk);
        res_ready_i = 0;

        $display("Time: %0t | Passagem 1 concluida (temp = a * R mod N): %h", $time, temp_res);

        // ==========================================
        // PASSAGEM 2: temp * b mod N
        // ==========================================
        wait(op_ready_o);
        @(posedge clk);
        op1_i = temp_res;
        op2_i = b;        // B puro, sem conversão
        op_valid_i = 1;
        
        @(posedge clk);
        op_valid_i = 0;

        wait(res_valid_o);
        @(posedge clk);
        res_ready_i = 1;
        
        $display("Time: %0t | Passagem 2 concluida. Resultado final: %d", $time, res_o);
        if (res_o == expected)
            $display("-> SUCESSO! Bateu com o esperado (%d)\n", expected);
        else
            $display("-> ERRO! Esperado: %d, Obtido: %d\n", expected, res_o);

        @(posedge clk);
        res_ready_i = 0;
    endtask

    initial begin
        $display("========================================");
        $display("   TESTE MONTGOMERY - MODO 2 PASSAGENS");
        $display("========================================");
        $display("Time: %0t ns\n", $time);

        // 1. RESET
        rst = 1;
        op_valid_i = 0;
        res_ready_i = 0;
        op1_i = 0;
        op2_i = 0;
        @(posedge clk);
        rst = 0;
        @(posedge clk);

        // 2. BATERIA DE TESTES
        // run_normal_modmul(opA, opB, Resultado_Esperado);
        
        run_normal_modmul(255'd5, 255'd7, 255'd35);
        
        run_normal_modmul(255'd100, 255'd200, 255'd20000);
        
        // Teste para forçar o limite (cálculo do esperado offline ou feito manualmente)
        run_normal_modmul(255'hFFFF, 255'hFFFF, 255'hFFFE0001);

        $display("========================================");
        $display("   TESTES CONCLUIDOS");
        $display("========================================\n");

        #(CLK_PERIOD * 5);
        $finish;
    end

    // Monitor opcional apenas se quiser ver a FSM rodando
    /*
    initial begin
        $monitor("Time: %0t | State: %s | valid: %b | ready: %b | res_o: %h",
                 $time, dut.current_state.name(), res_valid_o, op_ready_o, res_o);
    end
    */

endmodule