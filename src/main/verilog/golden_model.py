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

# ==========================================
# FUNÇÃO DO HARDWARE (Algorithm 1 da imagem)
# ==========================================
def montgomery_multiply(a_in, b_in, N, R, n_prime):
    # 2: t <- (a * b)
    t = a_in * b_in
    
    # 3: m <- t * n' mod R
    m = (t * n_prime) % R
    
    # 4: t <- (t + m * N) / R
    t = (t + m * N) // R
    
    # 5 a 9: if t >= N then return t - N else return t
    if t >= N:
        return t - N
    else:
        return t

# ==========================================
# PARÂMETROS DO SISTEMA
# ==========================================
N = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
R = 2**256

# Passo 1 (Offline): n' = -N^(-1) mod R
N_inv = mod_inverse(N, R)
n_prime = (-N_inv) % R

# Constante R^2 mod N
R2_mod_N = (R**2) % N

print("=== PARAMETROS GERADOS ===")
print("N       = {}".format(hex(N)))
print("n'      = {}".format(hex(n_prime)))
print("R^2 modN= {}\n".format(hex(R2_mod_N)))

# ==========================================
# ROTINA DE TESTES (Estratégia de 2 Passagens)
# ==========================================
def testar_multiplicacao(a, b):
    print("--- TESTE: {} * {} ---".format(a, b))
    
    # Passagem 1: Entrar no domínio (compensa o R^-1 da fórmula)
    # temp = Mont(a, R^2 mod N) = a * R mod N
    temp = montgomery_multiply(a, R2_mod_N, N, R, n_prime)
    print("Passagem 1 (a * R mod N) : {}".format(hex(temp)))
    
    # Passagem 2: Multiplicar pelo b puro
    # resultado = Mont(temp, b) = a * b mod N
    resultado = montgomery_multiply(temp, b, N, R, n_prime)
    
    # Validação do mundo real
    esperado = (a * b) % N
    
    print("Resultado Obtido         : {}".format(resultado))
    print("Resultado Esperado       : {}".format(esperado))
    
    if resultado == esperado:
        print("-> SUCESSO! A matematica do algoritmo e perfeita.\n")
    else:
        print("-> ERRO!\n")

# Rodando os mesmos testes do SystemVerilog
testar_multiplicacao(5, 7)
testar_multiplicacao(100, 200)
testar_multiplicacao(65535, 65535)