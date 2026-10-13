`timescale 1ns/1ps

// =============================================================================
// TopLevelPoseidon
//
// Roda o Poseidon padrao (PoseidonTopLevel_standard) e o Poseidon com fault
// detection (PoseidonTopLevel_wrapper) com a MESMA entrada e compara as saidas.
// Se forem diferentes, ativa fault_detected_o.
//
//  * A entrada so e entregue quando AMBOS estao prontos (os dois capturam no
//    mesmo ciclo e ficam sincronizados).
//  * Os dois terminam em tempos diferentes (o de fault detection faz encode e
//    decode a mais). Cada um segura sua saida estavel no estado final ate o
//    io_output_ready, entao nao precisa de registrador extra: a comparacao e
//    feita quando os dois estao com output_valid = 1.
//  * O resultado entregue na saida e o do design padrao.
// =============================================================================
module TopLevelPoseidon (
    input               io_input_valid,
    output              io_input_ready,
    input               io_input_last,
    input      [0:8][254:0] io_input_payload,
    input      [6:0]        round_idx,

    output              io_output_valid,
    input               io_output_ready,
    output              io_output_last,
    output     [0:8][254:0] io_output_payload,

    // ---- deteccao de falha ----
    output              fault_detected_o,   // 1 enquanto a saida valida for divergente
    output     [0:8]    fault_mask_o,       // quais elementos do estado divergem
    output logic        fault_sticky_o,     // fica em 1 ate o reset, apos qualquer divergencia

    input               clk,
    input               reset
);

    // ---------------- Entrada ----------------
    logic std_in_ready, flt_in_ready;
    logic both_in_ready;
    assign both_in_ready  = std_in_ready & flt_in_ready;
    assign io_input_ready = both_in_ready;

    logic in_valid_both;
    assign in_valid_both = io_input_valid & both_in_ready;

    // ---------------- Saida ----------------
    logic std_out_valid, flt_out_valid;
    logic std_out_last,  flt_out_last;
    logic [0:8][254:0] std_out_payload, flt_out_payload;

    logic both_out_valid;
    assign both_out_valid = std_out_valid & flt_out_valid;

    // Os dois so sao liberados juntos, depois de comparados
    logic out_ready_both;
    assign out_ready_both = io_output_ready & both_out_valid;

    // ---------------- Design padrao ----------------
    PoseidonTopLevel_standard #(.SEQUENTIAL(1)) u_standard (
        .io_input_valid   (in_valid_both),
        .io_input_ready   (std_in_ready),
        .io_input_last    (io_input_last),
        .io_input_payload (io_input_payload),
        .round_idx        (round_idx),
        .io_output_valid  (std_out_valid),
        .io_output_ready  (out_ready_both),
        .io_output_last   (std_out_last),
        .io_output_payload(std_out_payload),
        .clk              (clk),
        .reset            (reset)
    );

    // ---------------- Design com fault detection ----------------
    PoseidonTopLevel_wrapper #(.SEQUENTIAL(1)) u_fault (
        .io_input_valid   (in_valid_both),
        .io_input_ready   (flt_in_ready),
        .io_input_last    (io_input_last),
        .io_input_payload (io_input_payload),
        .round_idx        (round_idx),
        .io_output_valid  (flt_out_valid),
        .io_output_ready  (out_ready_both),
        .io_output_last   (flt_out_last),
        .io_output_payload(flt_out_payload),
        .clk              (clk),
        .reset            (reset)
    );

    // ---------------- Comparacao ----------------
    logic [0:8] elem_mismatch;
    for (genvar k = 0; k < 9; k++) begin : CMP
        assign elem_mismatch[k] = (std_out_payload[k] != flt_out_payload[k]);
    end

    assign fault_mask_o     = both_out_valid ? elem_mismatch : '0;
    assign fault_detected_o = both_out_valid & (|elem_mismatch);

    always_ff @(posedge clk or posedge reset) begin
        if (reset)                  fault_sticky_o <= 1'b0;
        else if (fault_detected_o)  fault_sticky_o <= 1'b1;
    end

    // ---------------- Saida do top ----------------
    assign io_output_valid   = both_out_valid;
    assign io_output_payload = std_out_payload;
    assign io_output_last    = std_out_last;

    // Somente simulacao
    // synthesis translate_off
    always @(posedge clk) begin
        if (fault_detected_o && io_output_ready)
            $error("[%0t] FALHA DETECTADA: saidas divergem. mask=%b", $time, fault_mask_o);
    end
    // synthesis translate_on

endmodule