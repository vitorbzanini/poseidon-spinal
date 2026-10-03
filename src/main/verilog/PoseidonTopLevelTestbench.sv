`timescale 1ns/1ps

module PoseidonTester ();

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(1, PoseidonTester);
    end

    localparam ClockPeriod = 10;
    localparam StateSize   = 9;
    localparam CaseNum     = 3;

    // init test cases
    logic [9*255-1:0] random_inputs[0:2];
    logic [255-1  :0] ref_outputs[0:2];
    
    initial begin
        // ==========================================
        // CASE 0 
        // ==========================================
        random_inputs[0][255*1-1:255*0] = 255'h2c31b76f79ec43792abeb60fc312d5907d8e1e65ccd7348344abb1594953e0fc;
        random_inputs[0][255*2-1:255*1] = 255'h5699fc150f68c6353b5b557f576df53d6ace988e132fe8a3b34c9d25410aace2;
        random_inputs[0][255*3-1:255*2] = 255'h2f4cf8a3c7f85b0a120fa9906e34e309b3b3b48824c32a468d70f835d0abb121;
        random_inputs[0][255*4-1:255*3] = 255'h2d7b0d831dc54c52bd4f12a493b12086c7cefc1257ec99a065a02ca8b181d3d9;
        random_inputs[0][255*5-1:255*4] = 255'h57717f05ce0eb4ffac62271fa0ded7c0938e813c7ca9c093f52bf51a5c84eaa1;
        random_inputs[0][255*6-1:255*5] = 255'h35c66831a0d5e6a615d8434307247c1639b860ac0e51db088a462ce455694c00;
        random_inputs[0][255*7-1:255*6] = 255'hefc77ca3994848c930847c18201a94436d5cc71844058f6a46e4af18a8f1c6e;
        random_inputs[0][255*8-1:255*7] = 255'h4650402fa402b6bce4833ecb497890a3fa88bfe17d1f581cd09e6d72db8a73df;
        random_inputs[0][255*9-1:255*8] = 255'h2ac931db5390a68274ec06f7f3b3b8c433cd692afce80da1a27d1ce1f0efb051;
        
        // Gabarito VALIDADO das 65 rodadas - CASE 0
        ref_outputs[0] = 255'h3a4caefe0d67e6dd0be592ca0d7c274cde7ae7a5d3b0f321a7ae3ae46a64b8c3;
        
        // ==========================================
        // CASE 1
        // ==========================================
        random_inputs[1][255*1-1:255*0] = 255'h62c838a9461d60da5d1b2c09b69ac5719d43ecb5eaa20ffcb67845f7b5298ac1;
        random_inputs[1][255*2-1:255*1] = 255'h56471b1cd018cb2a8ce500f5bb039ffb5ab416e4c1c92597d4c938be7528d329;
        random_inputs[1][255*3-1:255*2] = 255'h2fe3762c60793137af233cc8acc80f12e494e3577674c757140dbdfd8e34d286;
        random_inputs[1][255*4-1:255*3] = 255'h27f5e266a33ce1ce7b7e3c0ff9dc208daa761fde79ef13043d13880df26a91e4;
        random_inputs[1][255*5-1:255*4] = 255'h219715469ff34195e2cd87ac4acb8267c32ffde877906b5c8aa2c1100d97e57b;
        random_inputs[1][255*6-1:255*5] = 255'h1807394708c4cd299a0175d5b243a11eee3793d945825c045e2dd22b49dc7100;
        random_inputs[1][255*7-1:255*6] = 255'h3759563725df7bef5b924fe22c379cf15cc82927a5211061eb17c1b90ef794d2;
        random_inputs[1][255*8-1:255*7] = 255'h3dac033097dbea6d64dacc3fa7b5c0430a497d7bc1c8f566e093a81f14dc2457;
        random_inputs[1][255*9-1:255*8] = 255'h3ae6041f1d29bd3b6943669bcb20712b578d021b7f89b937d778b5897c247ad2;
        
        // Gabarito VALIDADO das 65 rodadas - CASE 1
        ref_outputs[1] = 255'h43801e84e8ef41312fe68dae3816751488ce7fe7d12132d3545f86efa38d5f76;

        // ==========================================
        // CASE 2
        // ==========================================
        random_inputs[2][255*1-1:255*0] = 255'h5d5cf53d7e90f1a5354834bc58cc3fac955f37a554af302a7282e3a693db6031;
        random_inputs[2][255*2-1:255*1] = 255'h6dcecc3b28d5007a4f6de64e7a19aff221078acd8fe61bcb3f2ca38bb57251d4;
        random_inputs[2][255*3-1:255*2] = 255'he7b94f14160e75cb28ad4d9ea99578b33b4f9ac3989dd1df1eb60ea6c00059d;
        random_inputs[2][255*4-1:255*3] = 255'h3356f26c281ab6e2cc37253f69d48ed55398a2df594bfd4fc8cfd85ff251f2cc;
        random_inputs[2][255*5-1:255*4] = 255'h2d8ee970888961e79feeb0cd962b76430606072bc082ef14be16713a734aad40;
        random_inputs[2][255*6-1:255*5] = 255'h70c0d0f0abc5ab734d67f70808d5bcc83080670f2898650846db3edcbcfc8d5e;
        random_inputs[2][255*7-1:255*6] = 255'h17dda1af1c465252939389b40cf7e44060508b76adc903c21bfafc3b3125b5db;
        random_inputs[2][255*8-1:255*7] = 255'h6d485981cf3ba66c51495d546f298b2afa4d214315119e5c655260821aa8e468;
        random_inputs[2][255*9-1:255*8] = 255'h549b07ae6c99841e1fab7dfe0ba2f4b20f7054f1681806285ddae892a1728491;
        
        // Gabarito VALIDADO das 65 rodadas - CASE 2
        ref_outputs[2] = 255'h628c54b6ffad60ea4952f071223b7cd450a6268c964b2993e1bd26c092ecce2b;
    end

    // generate clk and reset signal
    logic [49:0] cycle_counter;
    logic clk, reset;
    
    logic [6:0] round_idx;
    initial begin
        round_idx = 7'd0; 
    end

    initial begin cycle_counter = 0; end
    
    always @(posedge clk) begin
        if(reset) begin
            cycle_counter <= 0;
        end
        else begin
            cycle_counter <= cycle_counter + 1;
        end
    end
    
    initial begin
        clk = 0;
        forever #(ClockPeriod/2) clk = ~clk;
    end

    initial begin
        reset = 1;
        #(2*ClockPeriod) reset = 0;
    end

    // drive input ports
    logic [0:8][254:0] io_input_payload;
    logic io_input_valid;
    logic io_input_ready, io_input_last;
    logic input_handshake;
    assign input_handshake = io_input_valid & io_input_ready;
    logic [1:0] input_counter;

    always @(posedge clk) begin
        if(reset) begin
            input_counter <= 0;
            io_input_valid <= 0;
        end
        else begin
            if(input_counter < 3) begin
                io_input_valid <= 1'b1;
            end
            else begin
                io_input_valid <= 1'b0;
            end

            if(input_handshake) begin
                $display("input %d sent successfully", input_counter);
                input_counter <= input_counter + 1;
            end
        end
    end
    
    assign io_input_last = 1'b1;

    // Conecta o array de inputs de forma limpa
    genvar i;
    generate
        for(i = 0; i < 9; i++) begin : gen_inputs
            assign io_input_payload[i] = random_inputs[input_counter][255*(i+1)-1 : 255*i];
        end
    endgenerate

    // check output
    logic io_output_last, io_output_valid, io_output_ready;
    logic output_handshake;
    assign output_handshake = io_output_valid & io_output_ready;
    
    logic [0:8][254:0] io_output_payload;
    logic [1:0] output_counter;

    assign io_output_ready = 1'b1;
    
    always@(posedge clk) begin
        if(reset) begin
            output_counter <= 0;
        end
        else begin
            if(output_handshake) begin
                if( io_output_payload[0] != ref_outputs[output_counter]) begin
                    $display("error output %d: obtido %h, esperado %h", output_counter, io_output_payload[0], ref_outputs[output_counter]);
                    $display(" test fail !!!");
                    $finish();
                end else begin
                    $display("res %d: %h correct", output_counter, io_output_payload[0]);
                    output_counter <= output_counter + 1;
                end
            end

            if(output_counter == 3) begin
                $display("test success !!!");
                $display("Total latency for 3 hashes (Cycles): %d", cycle_counter);
                $display("Average latency per hash (Cycles): %d", cycle_counter / 3);
                $finish();
            end
        end
    end

    /*always @(posedge clk) begin
        if (!reset && cycle_counter % 2000 == 0)
            $display("[%0d] wrap=%s round=%0d sbox_idx=%0d | sbox_state=%s step=%0d | mix ready=%b done=%b",
                cycle_counter,
                poseidonInst.SEQUENTIAL_IMPLEMENTATION.current_state.name(),
                poseidonInst.SEQUENTIAL_IMPLEMENTATION.internal_round_idx,
                poseidonInst.SEQUENTIAL_IMPLEMENTATION.sbox_idx,
                poseidonInst.SEQUENTIAL_IMPLEMENTATION.sbox_inst.SERIAL_IMPLEMENTATION.state.name(),
                poseidonInst.SEQUENTIAL_IMPLEMENTATION.sbox_inst.SERIAL_IMPLEMENTATION.step,
                poseidonInst.SEQUENTIAL_IMPLEMENTATION.matrix_ready,
                poseidonInst.SEQUENTIAL_IMPLEMENTATION.matrix_done);
        end

    always @(posedge clk) if (cycle_counter > 1000000) begin
        $display("TIMEOUT"); $finish();
    end*/

    PoseidonTopLevel_wrapper poseidonInst(
        .io_input_valid    (io_input_valid   ),
        .io_input_ready    (io_input_ready   ),
        .io_input_last     (io_input_last    ),
        .io_input_payload  (io_input_payload ), 
        
        .round_idx         (round_idx        ), 
        
        .io_output_valid   (io_output_valid  ),
        .io_output_ready   (io_output_ready  ),
        .io_output_last    (io_output_last   ),
        .io_output_payload (io_output_payload), 
        .clk(clk),
        .reset(reset)
    );

endmodule