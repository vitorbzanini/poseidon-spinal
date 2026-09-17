module mix_layer_sequential #(
    parameter int unsigned N = 9
)(
    input  logic clk,
    input  logic reset,
    
    input  logic start,
    input  logic [0:N-1][254:0] state_in,  
    
    output logic ready,
    output logic done,
    output logic [0:N-1][254:0] state_out  
);

    localparam [254:0] R2_MOD_N = 255'h0748d9d99f59ff1105d314967254398f2b6cedcb87925c23c999e990f3f29c6d;

    localparam [254:0] MDS_MATRIX [0:8][0:8] = '{
        '{ 255'h19c308bd25b13848eef068e557794c72f62a247271c6bf1c38e38e38aaaaaaab, 255'h22c74bcc2615a595a8f7c0cf3616f401991f4acdb332b532e66666661999999a, 255'h6963af62e003892a5d1d50074e93217934daf23145cff68aba2e8ba200000001, 255'h6a44840c3b7b082cd99fb0b208d45b5a376dd6581553d4546aaaaaa9c0000001, 255'h6217dc5a0f85429f8dce7bb808267bb5bd02ed3d9d88753a3b13b13a3b13b13c, 255'h4a867dda0877876545809d29bd0c9d27fef9e96fa4913b23edb6db6d12492493, 255'h3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 255'h6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 255'h1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5 },
        '{ 255'h22c74bcc2615a595a8f7c0cf3616f401991f4acdb332b532e66666661999999a, 255'h6963af62e003892a5d1d50074e93217934daf23145cff68aba2e8ba200000001, 255'h6a44840c3b7b082cd99fb0b208d45b5a376dd6581553d4546aaaaaa9c0000001, 255'h6217dc5a0f85429f8dce7bb808267bb5bd02ed3d9d88753a3b13b13a3b13b13c, 255'h4a867dda0877876545809d29bd0c9d27fef9e96fa4913b23edb6db6d12492493, 255'h3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 255'h6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 255'h1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 255'h46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556 },
        '{ 255'h6963af62e003892a5d1d50074e93217934daf23145cff68aba2e8ba200000001, 255'h6a44840c3b7b082cd99fb0b208d45b5a376dd6581553d4546aaaaaa9c0000001, 255'h6217dc5a0f85429f8dce7bb808267bb5bd02ed3d9d88753a3b13b13a3b13b13c, 255'h4a867dda0877876545809d29bd0c9d27fef9e96fa4913b23edb6db6d12492493, 255'h3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 255'h6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 255'h1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 255'h46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 255'h6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001 },
        '{ 255'h6a44840c3b7b082cd99fb0b208d45b5a376dd6581553d4546aaaaaa9c0000001, 255'h6217dc5a0f85429f8dce7bb808267bb5bd02ed3d9d88753a3b13b13a3b13b13c, 255'h4a867dda0877876545809d29bd0c9d27fef9e96fa4913b23edb6db6d12492493, 255'h3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 255'h6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 255'h1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 255'h46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 255'h6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001, 255'h1163a5e6130ad2cad47be0679b0b7a00cc8fa566d9995a99733333330ccccccd },
        '{ 255'h6217dc5a0f85429f8dce7bb808267bb5bd02ed3d9d88753a3b13b13a3b13b13c, 255'h4a867dda0877876545809d29bd0c9d27fef9e96fa4913b23edb6db6d12492493, 255'h3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 255'h6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 255'h1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 255'h46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 255'h6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001, 255'h1163a5e6130ad2cad47be0679b0b7a00cc8fa566d9995a99733333330ccccccd, 255'h0b0a7175a27085d61d427619257d20c38e120f9ec30c08c2f3cf3cf3b6db6db7 },
        '{ 255'h4a867dda0877876545809d29bd0c9d27fef9e96fa4913b23edb6db6d12492493, 255'h3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 255'h6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 255'h1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 255'h46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 255'h6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001, 255'h1163a5e6130ad2cad47be0679b0b7a00cc8fa566d9995a99733333330ccccccd, 255'h0b0a7175a27085d61d427619257d20c38e120f9ec30c08c2f3cf3cf3b6db6db7, 255'h6ea8ab5b04d08339482b9407ac1a7cbf444c4b1a22e72944dd1745d080000001 },
        '{ 255'h3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 255'h6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 255'h1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 255'h46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 255'h6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001, 255'h1163a5e6130ad2cad47be0679b0b7a00cc8fa566d9995a99733333330ccccccd, 255'h0b0a7175a27085d61d427619257d20c38e120f9ec30c08c2f3cf3cf3b6db6db7, 255'h6ea8ab5b04d08339482b9407ac1a7cbf444c4b1a22e72944dd1745d080000001, 255'h64cea7c2c00361cf7a7514e599124c8a328ea4e137a587a61642c8582c8590b3 },
        '{ 255'h6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 255'h1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 255'h46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 255'h6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001, 255'h1163a5e6130ad2cad47be0679b0b7a00cc8fa566d9995a99733333330ccccccd, 255'h0b0a7175a27085d61d427619257d20c38e120f9ec30c08c2f3cf3cf3b6db6db7, 255'h6ea8ab5b04d08339482b9407ac1a7cbf444c4b1a22e72944dd1745d080000001, 255'h64cea7c2c00361cf7a7514e599124c8a328ea4e137a587a61642c8582c8590b3, 255'h6f1915afb28c42ba866cc45d093b19afc595bd2d8aa91829b555555460000001 },
        '{ 255'h1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 255'h46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 255'h6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001, 255'h1163a5e6130ad2cad47be0679b0b7a00cc8fa566d9995a99733333330ccccccd, 255'h0b0a7175a27085d61d427619257d20c38e120f9ec30c08c2f3cf3cf3b6db6db7, 255'h6ea8ab5b04d08339482b9407ac1a7cbf444c4b1a22e72944dd1745d080000001, 255'h64cea7c2c00361cf7a7514e599124c8a328ea4e137a587a61642c8582c8590b3, 255'h6f1915afb28c42ba866cc45d093b19afc595bd2d8aa91829b555555460000001, 255'h6aa770fa96ed0cdc062af9f2ea24419e803dd454ae12f879f5c28f5b3d70a3d8 }
    };

    logic         mul_valid, mul_ready, mul_res_valid;
    logic [254:0] mul_op1, mul_op2, mul_res;
    
    modmul #() matrix_multiplier (
        .clk(clk), .rst(reset),
        .op_valid_i(mul_valid), .op_ready_o(mul_ready),
        .op1_i(mul_op1), .op2_i(mul_op2),
        .res_valid_o(mul_res_valid), .res_ready_i(1'b1), .res_o(mul_res)
    );

    logic [254:0] acc_reg;
    logic [254:0] mod_add_res;

    ModAdder #() adder (
        .op1_i(acc_reg),
        .op2_i(mul_res),
        .res_o(mod_add_res)
    );

    typedef enum logic [3:0] {
        IDLE,
        MAC_P1_START, // Pass 1: Matriz * R^2 mod N
        MAC_P1_WAIT,
        MAC_P2_START, // Pass 2: Temp * state_in mod N
        MAC_P2_WAIT,
        ACCUMULATE,
        NEXT_ELEM,
        DONE
    } state_t;

    state_t current_state, next_state;
    logic [3:0] row_idx, next_row_idx;
    logic [3:0] col_idx, next_col_idx;

    logic [254:0] temp_reg; // Registrador para salvar a Passagem 1

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
            row_idx       <= '0;
            col_idx       <= '0;
        end else begin
            current_state <= next_state;
            row_idx       <= next_row_idx;
            col_idx       <= next_col_idx;
        end
    end

    // Registra a saída da primeira multiplicação
    always_ff @(posedge clk) begin
        if (current_state == MAC_P1_WAIT && mul_res_valid) begin
            temp_reg <= mul_res;
        end
    end

    always_comb begin
        next_state   = current_state;
        next_row_idx = row_idx;
        next_col_idx = col_idx;

        case (current_state)
            IDLE: begin
                if (start) begin
                    next_state   = MAC_P1_START;
                    next_row_idx = '0;
                    next_col_idx = '0;
                end
            end

            MAC_P1_START: begin
                if (mul_ready) next_state = MAC_P1_WAIT;
            end

            MAC_P1_WAIT: begin
                if (mul_res_valid) next_state = MAC_P2_START;
            end

            MAC_P2_START: begin
                if (mul_ready) next_state = MAC_P2_WAIT;
            end

            MAC_P2_WAIT: begin
                if (mul_res_valid) next_state = ACCUMULATE;
            end

            ACCUMULATE: begin
                next_state = NEXT_ELEM;
            end

            NEXT_ELEM: begin
                if (col_idx == N - 1) begin
                    next_col_idx = '0;
                    if (row_idx == N - 1) begin
                        next_state = DONE; // Terminou todas as linhas
                    end else begin
                        next_row_idx = row_idx + 1;
                        next_state   = MAC_P1_START;
                    end
                end else begin
                    next_col_idx = col_idx + 1;
                    next_state   = MAC_P1_START;
                end
            end

            DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // Mux para rotear as entradas certas do modmul a depender do passo
    always_comb begin
        if (current_state == MAC_P1_START || current_state == MAC_P1_WAIT) begin
            mul_op1 = MDS_MATRIX[row_idx][col_idx];
            mul_op2 = R2_MOD_N;
        end else begin
            mul_op1 = temp_reg;
            mul_op2 = state_in[col_idx];
        end
    end
    
    // Dispara a multiplicação nas etapas de START correspondentes
    assign mul_valid = (current_state == MAC_P1_START) || (current_state == MAC_P2_START);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            acc_reg   <= '0;
            state_out <= '0;
        end else begin
            if (current_state == IDLE || (current_state == NEXT_ELEM && col_idx == N - 1)) begin
                acc_reg <= '0;
            end else if (current_state == ACCUMULATE) begin
                acc_reg <= mod_add_res;
            end
            
            if (current_state == NEXT_ELEM && col_idx == N - 1) begin
                state_out[row_idx] <= acc_reg;
            end
        end
    end

    assign ready = (current_state == IDLE);
    assign done  = (current_state == DONE);

endmodule