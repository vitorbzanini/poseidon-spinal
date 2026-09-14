def golden_model_x5(x: int) -> str:
    """
    Calcula (x ** 5) % MODULUS e retorna o valor em hexadecimal.
    Utiliza pow() para exponenciação modular otimizada.
    """
    # Módulo definido para o campo do Poseidon
    MODULUS = int("73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001", 16)
    
    # pow(base, exp, mod) é muito mais rápido e eficiente em memória do que (x ** 5) % MODULUS
    resultado = pow(x, 5, MODULUS)
    
    # Formata o resultado em hexadecimal com 64 caracteres (256 bits) para facilitar 
    # a comparação direta com o log de simulação ($display("%h")) no testbench.
    return f"{resultado:064x}"

if __name__ == "__main__":
    # Exemplo prático de validação
    x_teste = int("2c31b76f79ec43792abeb60fc312d5907d8e1e65ccd7348344abb1594953e0fc", 16)
    resultado_hex = golden_model_x5(x_teste)
    
    print(f"Entrada x = {x_teste}")
    print(f"Saida (hex): {resultado_hex}")

    