N = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
R2 = 1 << 512
R2_mod_N = R2 % N

print("localparam [255:0] R2_MOD_N = 256'h{:064x};".format(R2_mod_N))