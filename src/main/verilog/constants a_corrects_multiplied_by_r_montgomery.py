P = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
A = [3, 5, 7, 11, 13, 17, 19, 23, 29]
R = (1 << 256) % P

def mod_inverse(value, mod):
    return pow(value, -1, mod)

print("=== COLA ISTO NO fault_encoder_in.sv ===")
print("    localparam logic [254:0] A_SCALARS [0:8] = '{")
for i, a in enumerate(A):
    mont = (a * R) % P
    comma = "," if i < 8 else ""
    print(f"        255'h{mont:064x}{comma}")
print("    };\n")

print("=== COLA ISTO NO fault_decoder_out.sv ===")
print("    localparam logic [254:0] INV_A_SCALARS [0:8] = '{")
for i, a in enumerate(A):
    inv = mod_inverse(a, P)
    mont_inv = (inv * R) % P
    comma = "," if i < 8 else ""
    print(f"        255'h{mont_inv:064x}{comma}")
print("    };")