package poseidon_pi_pkg;

    localparam int N = 9;

    // Matriz de permutacao PI (N x N): 1 em [k][SIGMA[k]], 0 no resto
    //   (PI * v)[k] = v[SIGMA[k]]
    localparam logic PI_MATRIX [0:8][0:8] = '{
        '{ 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0 },   // linha 0: 1 na coluna 5
        '{ 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0 },   // linha 1: 1 na coluna 6
        '{ 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0 },   // linha 2: 1 na coluna 7
        '{ 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0 },   // linha 3: 1 na coluna 4
        '{ 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0 },   // linha 4: 1 na coluna 3
        '{ 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0 },   // linha 5: 1 na coluna 0
        '{ 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1 },   // linha 6: 1 na coluna 8
        '{ 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0 },   // linha 7: 1 na coluna 1
        '{ 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0 }   // linha 8: 1 na coluna 2
    };

    // SIGMA[k]: de qual elemento ORIGINAL vem a posicao k do estado permutado
    localparam int SIGMA     [0:8] = '{ 5, 6, 7, 4, 3, 0, 8, 1, 2 };
    // SIGMA_INV[i]: em qual posicao do estado permutado mora o elemento original i
    localparam int SIGMA_INV [0:8] = '{ 5, 7, 8, 4, 3, 0, 1, 2, 6 };

    // Posicao do estado permutado onde o S-box age nas PARTIAL rounds
    // (e onde mora o elemento original 0)
    localparam int SBOX_POS_PARTIAL = 5;

endpackage