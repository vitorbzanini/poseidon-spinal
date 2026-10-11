# Gera poseidon_pi_pkg.sv com a matriz de permutacao PI (t x t) e os vetores auxiliares.
import random

N = 9

# --- Escolha da permutacao -------------------------------------------------
# Opcao 1: fixa (a usada na verificacao em Python)
SIGMA = [5, 6, 7, 4, 3, 0, 8, 1, 2]
# Opcao 2: aleatoria reproduzivel (descomente)
# SIGMA = list(range(N)); random.seed(42); random.shuffle(SIGMA)
# ---------------------------------------------------------------------------

assert sorted(SIGMA) == list(range(N)), "SIGMA nao e uma permutacao"

# PI[k][j] = 1 se j == SIGMA[k]  ->  (PI * v)[k] = v[SIGMA[k]]
PI = [[1 if j == SIGMA[k] else 0 for j in range(N)] for k in range(N)]
assert all(sum(r) == 1 for r in PI)                                  # 1 por linha
assert all(sum(PI[k][j] for k in range(N)) == 1 for j in range(N))   # 1 por coluna

SIGMA_INV = [SIGMA.index(i) for i in range(N)]
SBOX_POS_PARTIAL = SIGMA_INV[0]   # posicao onde mora o elemento original 0

L = []
L.append("// Gerado por generate_pi_pkg.py -- NAO editar a mao")
L.append("package poseidon_pi_pkg;")
L.append("")
L.append(f"    localparam int N = {N};")
L.append("")
L.append("    // Matriz de permutacao PI (N x N): 1 em [k][SIGMA[k]], 0 no resto")
L.append("    //   (PI * v)[k] = v[SIGMA[k]]")
L.append(f"    localparam logic PI_MATRIX [0:{N-1}][0:{N-1}] = '{{")
for k, row in enumerate(PI):
    comma = "," if k < N - 1 else ""
    L.append("        '{ " + ", ".join(f"1'b{v}" for v in row) + f" }}{comma}   // linha {k}: 1 na coluna {SIGMA[k]}")
L.append("    };")
L.append("")
L.append("    // SIGMA[k]: de qual elemento ORIGINAL vem a posicao k do estado permutado")
L.append(f"    localparam int SIGMA     [0:{N-1}] = '{{ " + ", ".join(map(str, SIGMA)) + " };")
L.append("    // SIGMA_INV[i]: em qual posicao do estado permutado mora o elemento original i")
L.append(f"    localparam int SIGMA_INV [0:{N-1}] = '{{ " + ", ".join(map(str, SIGMA_INV)) + " };")
L.append("")
L.append("    // Posicao do estado permutado onde o S-box age nas PARTIAL rounds")
L.append("    // (e onde mora o elemento original 0)")
L.append(f"    localparam int SBOX_POS_PARTIAL = {SBOX_POS_PARTIAL};")
L.append("")
L.append("endpackage")
open("poseidon_pi_pkg.sv", "w").write("\n".join(L) + "\n")
print("\n".join(L))