`timescale 1ns/1ps

// =============================================================================
// Testbench do PoseidonCompare_top
//
//  Parte 1 - casos limpos: os dois designs devem concordar (fault_detected_o = 0)
//            zeros, 1..9, N-1, e entradas aleatorias dentro do corpo.
//  Parte 2 - injecao de falha: inverte 1 bit do estado do design com fault
//            detection no meio de uma rodada (via force) e espera que o
//            comparador acuse (fault_detected_o = 1).
//  Parte 3 - reset limpa o fault_sticky_o e um caso limpo volta a passar.
//
//  Obs: a injecao usa force/release em sinal interno (precisa de simulador que
//  suporte, ex.: Questa/ModelSim, VCS, Xcelium, Vivado xsim). Verilator nao.
//  Nao ha vetor de referencia (golden): o teste compara os dois designs entre si.
// =============================================================================
module tb_PoseidonSequentialShared;

    // Corpo escalar de 255 bits (o mesmo do R2_MOD_N usado no sbox)
    localparam logic [254:0] FIELD_N =
        255'h73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;

    localparam int NUM_RANDOM     = 5;
    localparam int TIMEOUT_CYCLES = 20_000_000;

    // ---------------- Sinais ----------------
    logic clk = 1'b0;
    logic reset = 1'b1;
    always #5 clk = ~clk;   // 100 MHz

    logic              io_input_valid = 1'b0;
    wire               io_input_ready;
    logic              io_input_last  = 1'b0;
    logic [0:8][254:0] io_input_payload = '0;
    logic [6:0]        round_idx = 7'd0;

    wire               io_output_valid;
    logic              io_output_ready = 1'b0;
    wire               io_output_last;
    wire  [0:8][254:0] io_output_payload;

    wire               fault_detected_o;
    wire  [0:8]        fault_mask_o;
    wire               fault_sticky_o;

    // ---------------- DUT ----------------
    PoseidonSequentialShared_top #(.ERROR_ON_FAULT(1'b0)) dut (
        .io_input_valid   (io_input_valid),
        .io_input_ready   (io_input_ready),
        .io_input_last    (io_input_last),
        .io_input_payload (io_input_payload),
        .round_idx        (round_idx),
        .io_output_valid  (io_output_valid),
        .io_output_ready  (io_output_ready),
        .io_output_last   (io_output_last),
        .io_output_payload(io_output_payload),
        .fault_detected_o (fault_detected_o),
        .fault_mask_o     (fault_mask_o),
        .fault_sticky_o   (fault_sticky_o),
        .clk              (clk),
        .reset            (reset)
    );

    // ---------------- Contadores ----------------
    int n_pass = 0;
    int n_fail = 0;

    task automatic check(input bit cond, input string msg);
        if (cond) n_pass++;
        else begin
            n_fail++;
            $display("[%0t] FAIL: %s", $time, msg);
        end
    endtask

    // ---------------- Geradores de vetor ----------------
    function automatic logic [0:8][254:0] rand_vec();
        logic [0:8][254:0] v;
        logic [255:0]      t;
        for (int k = 0; k < 9; k++) begin
            t = {$urandom, $urandom, $urandom, $urandom,
                 $urandom, $urandom, $urandom, $urandom};
            v[k] = 255'(t % {1'b0, FIELD_N});
        end
        return v;
    endfunction

    function automatic logic [0:8][254:0] seq_vec();
        logic [0:8][254:0] v;
        for (int k = 0; k < 9; k++) v[k] = 255'(k + 1);
        return v;
    endfunction

    function automatic logic [0:8][254:0] max_vec();
        logic [0:8][254:0] v;
        for (int k = 0; k < 9; k++) v[k] = FIELD_N - 255'd1;
        return v;
    endfunction

    // ---------------- Injecao de falha ----------------
    bit inject_en    = 1'b0;
    int inject_round = 10;
    int inject_elem  = 0;
    int inject_bit   = 0;

    // No design sequencial os dois passos usam o MESMO latched_input / round idx,
    // entao a falha precisa dizer em qual passo cai:
    //   inject_pass = 0 -> passo padrao   (dut.fault_mode == 0)
    //   inject_pass = 1 -> passo codificado (dut.fault_mode == 1)
    // Em ambos os casos o comparador final deve acusar divergencia.
    bit inject_pass = 1'b1;

    // Dispara no inicio da rodada inject_round (sbox_idx == 0) do passo escolhido:
    // inverte 1 bit de latched_input[inject_elem].
    initial begin
        // xsim nao aceita force em bit/part-select nem com indice nao constante
        // em variavel: forca-se o vetor INTEIRO, ja com o bit invertido.
        logic [0:8][254:0] flipped_state;
        forever begin
            @(negedge clk);
            if (inject_en &&
                (dut.fault_mode === inject_pass) &&
                int'(dut.internal_round_idx) == inject_round &&
                dut.sbox_idx == 4'd0) begin
                flipped_state = dut.latched_input;
                flipped_state[inject_elem] = flipped_state[inject_elem] ^ (255'd1 << inject_bit);
                force dut.latched_input = flipped_state;
                @(posedge clk);
                #1;
                release dut.latched_input;
                inject_en = 1'b0;
                $display("[%0t] falha injetada: round=%0d elem=%0d bit=%0d",
                         $time, inject_round, inject_elem, inject_bit);
            end
        end
    end


    // ---------------- Execucao de um caso ----------------
    task automatic run_case(input string name,
                            input logic [0:8][254:0] vec,
                            input bit expect_fault);
        int cycles;
        begin
            $display("[%0t] --- %s ---", $time, name);

            // espera os dois designs ficarem prontos
            @(negedge clk);
            while (!io_input_ready) @(negedge clk);

            // 1 ciclo de handshake de entrada
            io_input_payload = vec;
            io_input_last    = 1'b1;
            io_input_valid   = 1'b1;
            @(posedge clk);
            @(negedge clk);
            io_input_valid   = 1'b0;
            io_input_last    = 1'b0;

            // espera a saida valida (os dois terminados)
            cycles = 0;
            while (!io_output_valid && cycles < TIMEOUT_CYCLES) begin
                @(negedge clk);
                cycles++;
            end
            check(io_output_valid === 1'b1, {name, ": timeout esperando io_output_valid"});

            if (io_output_valid) begin
                $display("[%0t] %s: saida em %0d ciclos", $time, name, cycles);

                check(io_output_last === 1'b1, {name, ": io_output_last deveria ser 1"});
                check((^io_output_payload) !== 1'bx, {name, ": payload com X"});

                if (expect_fault) begin
                    check(fault_detected_o === 1'b1,
                          {name, ": falha injetada NAO foi detectada"});
                    check(fault_mask_o !== 9'd0,
                          {name, ": fault_mask_o zerada apesar da falha"});
                    $display("[%0t] %s: fault_mask=%b", $time, name, fault_mask_o);
                end else begin
                    check(fault_detected_o === 1'b0,
                          {name, ": falso positivo (designs divergiram sem falha)"});
                    check(fault_mask_o === 9'd0,
                          {name, ": fault_mask_o diferente de zero sem falha"});
                    // sanidade: cada elemento deve estar reduzido no corpo
                    for (int k = 0; k < 9; k++)
                        check(io_output_payload[k] < FIELD_N,
                              $sformatf("%s: elemento %0d >= N", name, k));
                end

                // consome a saida
                io_output_ready = 1'b1;
                @(posedge clk);
                @(negedge clk);
                io_output_ready = 1'b0;
            end
        end
    endtask

    // ---------------- Watchdog global ----------------
    initial begin
        #(10ns * TIMEOUT_CYCLES * 20);
        $display("WATCHDOG: simulacao excedeu o tempo maximo");
        $finish;
    end

    // ---------------- Sequencia principal ----------------
    initial begin
        $dumpfile("tb_PoseidonSequentialShared.vcd");
        $dumpvars(0, tb_PoseidonSequentialShared);

        // reset
        repeat (5) @(negedge clk);
        reset = 1'b0;
        repeat (3) @(negedge clk);

        // -------- Parte 1: casos limpos --------
        run_case("zeros",   '0,         1'b0);
        run_case("seq_1_9", seq_vec(),  1'b0);
        run_case("max_N-1", max_vec(),  1'b0);
        for (int i = 0; i < NUM_RANDOM; i++)
            run_case($sformatf("random_%0d", i), rand_vec(), 1'b0);

        check(fault_sticky_o === 1'b0, "fault_sticky_o subiu nos casos limpos");

        // -------- Parte 2: injecao de falha --------
        // partial round (passo codificado)
        inject_pass = 1'b1;
        inject_en = 1'b1; inject_round = 10; inject_elem = 0; inject_bit = 0;
        run_case("fault_partial_r10_e0_b0", rand_vec(), 1'b1);

        // partial round (passo padrao)
        inject_pass = 1'b0;
        inject_en = 1'b1; inject_round = 10; inject_elem = 0; inject_bit = 0;
        run_case("fault_std_partial_r10_e0_b0", rand_vec(), 1'b1);
        inject_pass = 1'b1;

        // full round inicial
        inject_en = 1'b1; inject_round = 2; inject_elem = 3; inject_bit = 100;
        run_case("fault_full_r2_e3_b100", rand_vec(), 1'b1);

        // full round final
        inject_en = 1'b1; inject_round = 62; inject_elem = 8; inject_bit = 254;
        run_case("fault_full_r62_e8_b254", rand_vec(), 1'b1);

        // ultima rodada
        inject_en = 1'b1; inject_round = 64; inject_elem = 5; inject_bit = 7;
        run_case("fault_last_r64_e5_b7", rand_vec(), 1'b1);

        check(fault_sticky_o === 1'b1, "fault_sticky_o deveria estar em 1 apos as falhas");

        // -------- Parte 3: reset limpa o sticky --------
        reset = 1'b1;
        repeat (3) @(negedge clk);
        reset = 1'b0;
        repeat (3) @(negedge clk);
        check(fault_sticky_o === 1'b0, "fault_sticky_o nao foi limpo pelo reset");

        run_case("pos_reset_random", rand_vec(), 1'b0);

        // -------- Resumo --------
        $display("==================================================");
        $display(" checks OK: %0d   FALHAS: %0d", n_pass, n_fail);
        if (n_fail == 0) $display(" RESULTADO: PASS");
        else             $display(" RESULTADO: FAIL");
        $display("==================================================");
        $finish;
    end

endmodule