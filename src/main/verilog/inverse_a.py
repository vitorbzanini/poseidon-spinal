P = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
A = [3, 5, 7, 11, 13, 17, 19, 23, 29]

R = (1 << 256) % P   # fator de Montgomery

def mod_inverse(value, mod):
    return pow(value, -1, mod)

print("=== COLA ISTO NO fault_decoder_out.sv (INV_A_MONT) ===")
for i, val in enumerate(A):
    inv = mod_inverse(val, P)
    inv_mont = (inv * R) % P          # <-- A^-1 * R mod P
    comma = "," if i < len(A) - 1 else ""   # sem vírgula no último elemento
    print(f"255'h{inv_mont:064x}{comma}")