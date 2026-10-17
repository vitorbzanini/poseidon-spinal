# =============================================================================
# poseidon_ooc.xdc
#
# Constraints para implementacao OUT-OF-CONTEXT (post-route) dos 4 designs:
#   1. Poseidon padrao            (PoseidonTopLevel_standard)
#   2. Ramo codificado            (PoseidonTopLevel_wrapper, branch fault-detection)
#   3. Sequencial compartilhado   (PoseidonSequentialShared_top)
#   4. Paralelo lado a lado       (TopLevelPoseidon / PoseidonCompare_top)
#
# Os 4 tops usam as mesmas portas de clock e reset (clk, reset), entao este
# arquivo serve para todos sem alteracao. Use o MESMO periodo, a MESMA parte e
# a MESMA configuracao do modmul nos 4 casos para a comparacao ser justa.
#
# Nao ha constraints de pino (LOC / IOSTANDARD): em out-of-context o Vivado nao
# coloca os ~4600 bits de I/O em pinos fisicos.
#
# Fmax estimado = 1 / (PERIODO - WNS)   [WNS do report_timing_summary pos-route]
# =============================================================================

# ---------------- Clock ----------------
# Altere so este valor para varrer frequencias (ns). 10.000 = 100 MHz.
set clk_period 10.000

create_clock -name clk -period $clk_period [get_ports clk]

# Posicao do buffer de clock em modo OOC (7-series). Deixa o roteamento do clock
# realista, sem isso o skew em OOC fica otimista.
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]

# Sem incerteza extra: mede o design, nao a margem de jitter do board
set_clock_uncertainty 0.000 [get_clocks clk]

# ---------------- I/O ----------------
# Atrasos de I/O zero em relacao ao clock: nenhum caminho de I/O e penalizado,
# o periodo critico e definido pelos caminhos registrador -> registrador
# (modmul), que e o que importa para o Fmax.
set_input_delay  -clock clk 0.000 [get_ports -filter {NAME != clk && NAME != reset} -of_objects [all_inputs]]
set_output_delay -clock clk 0.000 [all_outputs]

# ---------------- Reset ----------------
# Reset e assincrono (posedge reset) e vem de fora do bloco: nao e caminho
# temporizado.
set_false_path -from [get_ports reset]

# ---------------- Atividade para potencia (vectorless) ----------------
# Estimativa sem simulacao. Para numero confiavel, gere um SAIF da simulacao
# post-route e use: read_saif ...; report_power
set_switching_activity -default_toggle_rate 12.5 -default_static_probability 0.5 [get_nets -hier -filter {TYPE == SIGNAL}]
