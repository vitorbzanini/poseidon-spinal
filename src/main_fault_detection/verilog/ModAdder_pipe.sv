// ModAdder_pipe - soma modular em 2 estagios (latencia fixa de 2 ciclos)
//
// Mesmo resultado do ModAdder (original) para qualquer entrada de 255 bits, mas
// a cadeia de carry de 255 bits e cortada em duas de ~128 bits com o carry
// registrado entre elas:
//   estagio 1 : metade baixa  -> s_lo = a+b   e   t_lo = a+b+C      (em paralelo)
//   estagio 2 : metade alta   -> s_hi, t_hi (usando os carries registrados)
//               res = (t[256:255] != 0) ? t[254:0] : s[254:0]
// Entradas devem ficar ESTAVEIS por 2 ciclos; res_o e valido 2 ciclos depois.
module ModAdder_pipe #(
    parameter DATA_WIDTH = 255,
    parameter LO = 128,
    // R - MODULUS (R = 2^DATA_WIDTH)
    parameter [DATA_WIDTH-1:0] MOD_COMPENSATION = 255'hc1258acd66282b7ccc627f7f65e27faac425bfd0001a40100000000ffffffff
)(
    input  wire                  clk,
    input  wire [DATA_WIDTH-1:0] op1_i,
    input  wire [DATA_WIDTH-1:0] op2_i,
    output reg  [DATA_WIDTH-1:0] res_o
);
    localparam HI = DATA_WIDTH - LO;

    // ---- estagio 1: metade baixa ----
    reg [LO:0]   s_lo;        // a_lo + b_lo          (carry em [LO])
    reg [LO+1:0] t_lo;        // a_lo + b_lo + C_lo   (carry 0..2 em [LO+1:LO])
    reg [HI-1:0] a_hi, b_hi;
    always @(posedge clk) begin
        s_lo <= {1'b0, op1_i[LO-1:0]} + {1'b0, op2_i[LO-1:0]};
        t_lo <= {2'b00, op1_i[LO-1:0]} + {2'b00, op2_i[LO-1:0]} + {2'b00, MOD_COMPENSATION[LO-1:0]};
        a_hi <= op1_i[DATA_WIDTH-1:LO];
        b_hi <= op2_i[DATA_WIDTH-1:LO];
    end

    // ---- estagio 2: metade alta + selecao ----
    wire [HI:0]   s_hi = {1'b0, a_hi} + {1'b0, b_hi} + {{HI{1'b0}}, s_lo[LO]};
    wire [HI+1:0] t_hi = {2'b00, a_hi} + {2'b00, b_hi} + {2'b00, MOD_COMPENSATION[DATA_WIDTH-1:LO]}
                       + {{HI{1'b0}}, t_lo[LO+1:LO]};

    (* max_fanout = 32 *) wire sel;
    assign sel = t_hi[HI+1] | t_hi[HI];

    always @(posedge clk)
        res_o <= sel ? {t_hi[HI-1:0], t_lo[LO-1:0]} : {s_hi[HI-1:0], s_lo[LO-1:0]};
endmodule