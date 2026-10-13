# -*- coding: utf-8 -*-

def extended_gcd(a, b):
    if a == 0:
        return b, 0, 1
    gcd, x1, y1 = extended_gcd(b % a, a)
    x = y1 - (b // a) * x1
    y = x1
    return gcd, x, y

def mod_inverse(a, m):
    gcd, x, _ = extended_gcd(a % m, m)
    if gcd != 1:
        raise ValueError("Inverso nao existe")
    return (x % m + m) % m

# Seus valores
N = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
R = 2**256

# Calcular n' = -N^(-1) mod R
N_inv = mod_inverse(N, R)
n_prime = (-N_inv) % R

print("parameter logic [255:0] N_LINE = 256'h{:064x};".format(n_prime))