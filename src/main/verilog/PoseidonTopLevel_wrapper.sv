module PoseidonTopLevel_wrapper (
    input               io_input_valid,
    output              io_input_ready,
    input               io_input_last,
    
    input      [0:8][254:0] io_input_payload, 
    
    output              io_output_valid,
    input               io_output_ready,
    output              io_output_last,
    
    output     [0:8][254:0] io_output_payload, 
    
    input               clk,
    input               reset
);

    logic [0:8] io_input_valid_sboxes;
    logic [0:8] io_input_ready_sboxes;
    logic [0:8] io_input_last_sboxes;
    logic [0:8][254:0] io_input_payload_sboxes;
    
    logic [0:8] io_output_valid_sboxes;
    logic [0:8] io_output_ready_sboxes;
    logic [0:8][254:0] io_output_payload_sboxes;
    
    generate
        genvar j;
        for (j = 0; j < 9; j++) begin : gen_inputs
            assign io_input_valid_sboxes[j]   = io_input_valid;
            assign io_input_last_sboxes[j]    = io_input_last;
            assign io_input_payload_sboxes[j] = io_input_payload[j];
        end
    endgenerate

    assign io_input_ready = &io_input_ready_sboxes;

    generate
        genvar i;
        for (i = 0; i < 9; i++) begin : gen_sboxes 
            sbox sbox_inst (
                .io_input_valid(io_input_valid_sboxes[i]),
                .io_input_ready(io_input_ready_sboxes[i]),
                .io_input_last(io_input_last_sboxes[i]),
                .io_input_payload(io_input_payload_sboxes[i]),
                
                .io_output_valid(io_output_valid_sboxes[i]),
                .io_output_ready(io_output_ready_sboxes[i]),
                //.io_output_last(io_output_last_sboxes[i]),
                .io_output_payload(io_output_payload_sboxes[i]),
                
                .clk(clk),
                .reset(reset)
            );
        end
    endgenerate
    
    logic matrix_start;
    logic matrix_ready;
    logic matrix_done;
    logic [0:8][254:0] matrix_state_out;

    wire all_sboxes_valid = &io_output_valid_sboxes;
    assign matrix_start = all_sboxes_valid & matrix_ready;

    generate
        genvar k;
        for (k = 0; k < 9; k++) begin : gen_sbox_ready
            assign io_output_ready_sboxes[k] = matrix_start;
        end
    endgenerate

    logic [0:8][254:0] latched_sbox_payload;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            latched_sbox_payload <= '0;
        end else if (matrix_start) begin
            latched_sbox_payload <= io_output_payload_sboxes;
        end
    end

    mix_layer_sequential #(.N(9)) mix_layer_inst (
        .clk(clk),
        .reset(reset),
        .start(matrix_start),
        .state_in(latched_sbox_payload), 
        .ready(matrix_ready),
        .done(matrix_done),
        .state_out(matrix_state_out)
    );

    assign io_output_valid   = matrix_done;
    assign io_output_payload = matrix_state_out;

    reg last_reg;
    assign io_output_last = last_reg;
    always_ff @(posedge clk) begin
        if (io_input_valid && io_input_ready) begin
            last_reg <= io_input_last;
        end
    end
    
endmodule