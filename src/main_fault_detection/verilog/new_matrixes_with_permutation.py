P = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
N = 9
A = [3, 5, 7, 11, 13, 17, 19, 23, 29]

# AQUI ESTÁ A CHAVE: Fator de Montgomery R = 2^256 mod P
R = (1 << 256) % P

# --- PERMUTACAO (tem que ser IGUAL a SIGMA do generate_pi_pkg.py) ---
SIGMA = [5, 6, 7, 4, 3, 0, 8, 1, 2]
assert sorted(SIGMA) == list(range(N))

# PI[k][j] = 1 se j == SIGMA[k]   ->   (PI * v)[k] = v[SIGMA[k]]
PI     = [[1 if j == SIGMA[k] else 0 for j in range(N)] for k in range(N)]
PI_INV = [[PI[j][i] for j in range(N)] for i in range(N)]      # inversa = transposta

def matmul(X, Y):
    return [[sum(X[i][k] * Y[k][j] for k in range(N)) % P for j in range(N)] for i in range(N)]

def permute(M):
    # M' = PI x M x PI^-1   (equivale a M'[k][l] = M[SIGMA[k]][SIGMA[l]])
    Mp = matmul(matmul(PI, M), PI_INV)
    assert all(Mp[k][l] == M[SIGMA[k]][SIGMA[l]] for k in range(N) for l in range(N))
    return Mp

def mod_inverse(value, mod):
    return pow(value, -1, mod)

# Colar a MDS_MATRIX original aqui (Raw)
MDS_MATRIX = [
    [0x19c308bd25b13848eef068e557794c72f62a247271c6bf1c38e38e38aaaaaaab, 0x22c74bcc2615a595a8f7c0cf3616f401991f4acdb332b532e66666661999999a, 0x6963af62e003892a5d1d50074e93217934daf23145cff68aba2e8ba200000001, 0x6a44840c3b7b082cd99fb0b208d45b5a376dd6581553d4546aaaaaa9c0000001, 0x6217dc5a0f85429f8dce7bb808267bb5bd02ed3d9d88753a3b13b13a3b13b13c, 0x4a867dda0877876545809d29bd0c9d27fef9e96fa4913b23edb6db6d12492493, 0x3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 0x6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 0x1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5],
    [0x22c74bcc2615a595a8f7c0cf3616f401991f4acdb332b532e66666661999999a, 0x6963af62e003892a5d1d50074e93217934daf23145cff68aba2e8ba200000001, 0x6a44840c3b7b082cd99fb0b208d45b5a376dd6581553d4546aaaaaa9c0000001, 0x6217dc5a0f85429f8dce7bb808267bb5bd02ed3d9d88753a3b13b13a3b13b13c, 0x4a867dda0877876545809d29bd0c9d27fef9e96fa4913b23edb6db6d12492493, 0x3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 0x6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 0x1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 0x46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556],
    [0x6963af62e003892a5d1d50074e93217934daf23145cff68aba2e8ba200000001, 0x6a44840c3b7b082cd99fb0b208d45b5a376dd6581553d4546aaaaaa9c0000001, 0x6217dc5a0f85429f8dce7bb808267bb5bd02ed3d9d88753a3b13b13a3b13b13c, 0x4a867dda0877876545809d29bd0c9d27fef9e96fa4913b23edb6db6d12492493, 0x3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 0x6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 0x1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 0x46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 0x6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001],
    [0x6a44840c3b7b082cd99fb0b208d45b5a376dd6581553d4546aaaaaa9c0000001, 0x6217dc5a0f85429f8dce7bb808267bb5bd02ed3d9d88753a3b13b13a3b13b13c, 0x4a867dda0877876545809d29bd0c9d27fef9e96fa4913b23edb6db6d12492493, 0x3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 0x6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 0x1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 0x46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 0x6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001, 0x1163a5e6130ad2cad47be0679b0b7a00cc8fa566d9995a99733333330ccccccd],
    [0x6217dc5a0f85429f8dce7bb808267bb5bd02ed3d9d88753a3b13b13a3b13b13c, 0x4a867dda0877876545809d29bd0c9d27fef9e96fa4913b23edb6db6d12492493, 0x3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 0x6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 0x1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 0x46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 0x6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001, 0x1163a5e6130ad2cad47be0679b0b7a00cc8fa566d9995a99733333330ccccccd, 0x0b0a7175a27085d61d427619257d20c38e120f9ec30c08c2f3cf3cf3b6db6db7],
    [0x4a867dda0877876545809d29bd0c9d27fef9e96fa4913b23edb6db6d12492493, 0x3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 0x6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 0x1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 0x46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 0x6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001, 0x1163a5e6130ad2cad47be0679b0b7a00cc8fa566d9995a99733333330ccccccd, 0x0b0a7175a27085d61d427619257d20c38e120f9ec30c08c2f3cf3cf3b6db6db7, 0x6ea8ab5b04d08339482b9407ac1a7cbf444c4b1a22e72944dd1745d080000001],
    [0x3dd414f92742ed7bd70dc88cd1efeaad81febddf77769776eeeeeeee66666667, 0x6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 0x1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 0x46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 0x6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001, 0x1163a5e6130ad2cad47be0679b0b7a00cc8fa566d9995a99733333330ccccccd, 0x0b0a7175a27085d61d427619257d20c38e120f9ec30c08c2f3cf3cf3b6db6db7, 0x6ea8ab5b04d08339482b9407ac1a7cbf444c4b1a22e72944dd1745d080000001, 0x64cea7c2c00361cf7a7514e599124c8a328ea4e137a587a61642c8582c8590b3],
    [0x6caeccddf703a573b0063a878907ba84fe81c9c2cffe763f0fffffff10000001, 0x1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 0x46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 0x6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001, 0x1163a5e6130ad2cad47be0679b0b7a00cc8fa566d9995a99733333330ccccccd, 0x0b0a7175a27085d61d427619257d20c38e120f9ec30c08c2f3cf3cf3b6db6db7, 0x6ea8ab5b04d08339482b9407ac1a7cbf444c4b1a22e72944dd1745d080000001, 0x64cea7c2c00361cf7a7514e599124c8a328ea4e137a587a61642c8582c8590b3, 0x6f1915afb28c42ba866cc45d093b19afc595bd2d8aa91829b555555460000001],
    [0x1b46fa31af7059b6a2a432d4b6f8e788c868db4bffff9d2cf0f0f0f0b4b4b4b5, 0x46d8580827a75ac891152076b08d923c24f3e43ab8e28d8d9c71c71bd5555556, 0x6dd3abfdf187ba0e815f38736770e79941dc14a486bb13c9286bca1a00000001, 0x1163a5e6130ad2cad47be0679b0b7a00cc8fa566d9995a99733333330ccccccd, 0x0b0a7175a27085d61d427619257d20c38e120f9ec30c08c2f3cf3cf3b6db6db7, 0x6ea8ab5b04d08339482b9407ac1a7cbf444c4b1a22e72944dd1745d080000001, 0x64cea7c2c00361cf7a7514e599124c8a328ea4e137a587a61642c8582c8590b3, 0x6f1915afb28c42ba866cc45d093b19afc595bd2d8aa91829b555555460000001, 0x6aa770fa96ed0cdc062af9f2ea24419e803dd454ae12f879f5c28f5b3d70a3d8]
]

# 1. Matriz para FULL ROUNDS (Cancela x^5 em todas as colunas)
M_full = [[0]*N for _ in range(N)]
for i in range(N):
    for j in range(N):
        inv_a_j_5 = mod_inverse(pow(A[j], 5, P), P)
        # INCLUI O FATOR DE MONTGOMERY 'R' AQUI!
        M_full[i][j] = (MDS_MATRIX[i][j] * R * A[i] * inv_a_j_5) % P

# 2. Matriz para PARTIAL ROUNDS (Cancela x^5 só na col 0, e x^1 nas cols 1..8)
M_partial = [[0]*N for _ in range(N)]
for i in range(N):
    for j in range(N):
        if j == 0:
            inv_a = mod_inverse(pow(A[0], 5, P), P)
        else:
            inv_a = mod_inverse(A[j], P)
            
        # INCLUI O FATOR DE MONTGOMERY 'R' AQUI!
        M_partial[i][j] = (MDS_MATRIX[i][j] * R * A[i] * inv_a) % P

# 3. Aplica a permutacao: M' = PI x M x PI^-1   (o R de Montgomery passa direto)
M_full    = permute(M_full)
M_partial = permute(M_partial)

# Imprimir formatado para o SystemVerilog Package
print("    // =================================================")
print("    // 2A. ARRAY 2D: FAULT_MDS_MATRIX_FULL (MONTGOMERY)")
print("    // =================================================")
print(f"    localparam logic [254:0] FAULT_MDS_MATRIX_FULL [0:{N-1}][0:{N-1}] = '{{")
for i, row in enumerate(M_full):
    formatted_row = ", ".join([f"255'h{val:064x}" for val in row])
    comma = "," if i < len(M_full) - 1 else ""
    print(f"        '{{ {formatted_row} }}{comma}")
print("    };\n")

print("    // =================================================")
print("    // 2B. ARRAY 2D: FAULT_MDS_MATRIX_PARTIAL (MONTGOMERY)")
print("    // =================================================")
print(f"    localparam logic [254:0] FAULT_MDS_MATRIX_PARTIAL [0:{N-1}][0:{N-1}] = '{{")
for i, row in enumerate(M_partial):
    formatted_row = ", ".join([f"255'h{val:064x}" for val in row])
    comma = "," if i < len(M_partial) - 1 else ""
    print(f"        '{{ {formatted_row} }}{comma}")
print("    };")