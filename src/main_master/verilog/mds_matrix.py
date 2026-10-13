P = 0x73EDA753299D7D483339D80809A1D80553BDA402FFFE5BFEFFFFFFFF00000001

def get_inverse(x):
    """get the modular inverse of x (mod p )"""
    """ the inverse of x equals to pow(x,p-2) mod p """
    p_bin = bin(P - 2)[2:]
    inverse = 1
    tmp = x % P
    for i in range(len(p_bin)):
        if p_bin[len(p_bin) - i - 1] == "1":
            inverse = (inverse * tmp) % P
        tmp = (tmp * tmp) % P

    return inverse

def get_mds_matrix(t):
    mds_x = range(0, t)
    mds_y = range(t, 2 * t)
    mds_matrix = []

    for x in mds_x:
        mds_vec = []
        for y in mds_y:
            mds_vec.append(get_inverse(x + y))
        mds_matrix.append(mds_vec)

    return mds_matrix

t = 9
mds_matrix = get_mds_matrix(t)

# --- Geração do código SystemVerilog ---
print("localparam [254:0] MDS_MATRIX [0:8][0:8] = '{")
for i in range(t):
    # Formata cada valor em hexadecimal com 64 caracteres de preenchimento (256 bits)
    row_str = ", ".join([f"255'h{val:064x}" for val in mds_matrix[i]])
    
    # Adiciona a vírgula no final de cada linha, exceto na última
    if i < t - 1:
        print(f"    '{{ {row_str} }},")
    else:
        print(f"    '{{ {row_str} }}")
print("};")