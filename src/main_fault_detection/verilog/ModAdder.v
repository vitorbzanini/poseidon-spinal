// ModAdder - soma modular com as duas somas em PARALELO (antes eram em serie).
//
//   original :  res1 = a + b ;  res2 = res1 + C ;  res = (c1 | c2) ? res2 : res1
//               -> duas cadeias de carry de 255 bits uma depois da outra
//
//   aqui     :  res1 = a + b            (cadeia A)
//               s3   = a + b + C        (cadeia B, em paralelo com a A)
//               res  = (s3[256:255] != 0) ? s3[254:0] : res1
//
//   Igual ao original para QUALQUER entrada de 255 bits (nao so < MODULUS):
//     s3 >> 255 = carry1 + carry2   =>   (carry1 | carry2) == (s3[256:255] != 0)
//     s3[254:0] = (res1 + C) mod 2^255 = res2
module ModAdder #(
    // width of modulus
    parameter DATA_WIDTH = 255,
    // the modulus of ModAdder
    parameter MODULUS = 255'h73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001,
    // R = exp(2, DATA_WIDTH)  MOD_COMPENSATION = R - MODULUS
    parameter MOD_COMPENSATION = 255'hc1258acd66282b7ccc627f7f65e27faac425bfd0001a40100000000ffffffff
)(
    input  wire [DATA_WIDTH-1:0] op1_i,
    input  wire [DATA_WIDTH-1:0] op2_i,

    output wire [DATA_WIDTH-1:0] res_o
    );

    wire [DATA_WIDTH-1:0] res1;
    wire [DATA_WIDTH+1:0] s3;

    assign res1 = op1_i + op2_i;
    assign s3   = {2'b00, op1_i} + {2'b00, op2_i} + {2'b00, MOD_COMPENSATION};

    // o seletor alimenta 255 bits: pede ao Vivado para replicar o driver
    (* max_fanout = 32 *) wire sel;
    assign sel   = s3[DATA_WIDTH+1] | s3[DATA_WIDTH];
    assign res_o = sel ? s3[DATA_WIDTH-1:0] : res1;

endmodule