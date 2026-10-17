# =============================================================================
# poseidon_reports.tcl
#
# Gera os reports pos-route (area, timing, Fmax, potencia, por modulo) de UM
# design. Rode uma vez em cada um dos 4 projetos:
#   1. Poseidon padrao  2. ramo codificado  3. sequencial  4. paralelo
#
# USO (console Tcl do Vivado, depois do Route Design):
#     source poseidon_reports.tcl
# ou em batch:
#     vivado -mode batch -source poseidon_reports.tcl
#
# Variaveis opcionais (defina ANTES do source, senao usa o default):
#     set run_name   impl_1                  ;# run de implementacao
#     set out_dir    ./reports_sequencial    ;# pasta de saida (use um nome por design!)
#     set saif_file  /caminho/sim.saif       ;# SAIF da simulacao post-route (potencia confiavel)
#     set saif_strip tb_.../dut              ;# caminho do DUT dentro do SAIF (strip_path)
#
# Para ver os modulos separados no relatorio, mantenha a hierarquia na sintese:
#     Settings -> Synthesis -> flatten_hierarchy = none
# =============================================================================

proc setdef {name val} {
    upvar #0 $name v
    if {![info exists v]} { set v $val }
}

setdef run_name   impl_1
setdef out_dir /home/vitor/poseidon_reports/sequencial
setdef saif_file  ""
setdef saif_strip ""
# Modulos que viram uma linha propria no resumo (nome do modulo, nao da instancia)
setdef module_list {
    PoseidonTopLevel_standard PoseidonTopLevel_wrapper
    mix_layer_sequential mix_layer_standard mix_layer_fault mix_layer_shared
    sbox sbox_shared modmul ModAdder fault_encoder_in fault_decoder_out
}

file mkdir $out_dir
file mkdir $out_dir/modules

# ---------------- helpers ----------------
proc write_text {f txt} {
    set fh [open $f w]
    puts $fh $txt
    close $fh
}

proc safe_name {s} {
    regsub -all {[^A-Za-z0-9_]} $s _ s
    return $s
}

# Extrai LUT / FF / DSP / BRAM do texto de report_utilization (7-series e UltraScale)
proc parse_util {txt} {
    array set r {lut NA ff NA dsp NA bram NA}
    if {[regexp {\|\s*(?:Slice|CLB) LUTs\*?\s*\|\s*(\d+)}       $txt -> v]} { set r(lut)  $v }
    if {[regexp {\|\s*(?:Slice|CLB) Registers\s*\|\s*(\d+)}     $txt -> v]} { set r(ff)   $v }
    if {[regexp {\|\s*DSPs\s*\|\s*(\d+)}                        $txt -> v]} { set r(dsp)  $v }
    if {[regexp {\|\s*Block RAM Tile\s*\|\s*([0-9.]+)}          $txt -> v]} { set r(bram) $v }
    return [array get r]
}

# ---------------- abre o design ----------------
if {[llength [get_designs -quiet]] == 0} {
    open_run $run_name
}
set st [get_property STATUS [get_runs $run_name]]
if {![string match "*route_design Complete*" $st]} {
    puts "AVISO: o run $run_name nao esta com route_design completo (status: $st)."
    puts "       Os numeros abaixo NAO sao pos-route."
}
set top_name [get_property TOP [current_design]]
set part     [get_property PART [current_design]]
puts "Top: $top_name   Parte: $part   Saida: $out_dir"

# ---------------- SAIF (opcional) ----------------
if {$saif_file ne ""} {
    puts "Lendo SAIF: $saif_file"
    if {$saif_strip ne ""} {
        read_saif -strip_path $saif_strip $saif_file
    } else {
        read_saif $saif_file
    }
}

# ---------------- reports do design inteiro ----------------
report_utilization -file $out_dir/util_full.rpt
report_utilization -hierarchical -hierarchical_depth 8 -hierarchical_percentages \
                   -file $out_dir/util_hier.rpt
report_timing_summary -delay_type min_max -max_paths 10 -report_unconstrained \
                      -check_timing_verbose -file $out_dir/timing_summary.rpt
report_timing -delay_type max -max_paths 10 -sort_by slack -input_pins \
              -file $out_dir/timing_top10_setup.rpt
report_clocks            -file $out_dir/clocks.rpt
report_clock_utilization -file $out_dir/clock_utilization.rpt
report_route_status      -file $out_dir/route_status.rpt
report_drc               -file $out_dir/drc.rpt

# Potencia (texto retornado, para extrair os totais e salvar o arquivo)
set ptxt [report_power -return_string]
write_text $out_dir/power_full.rpt $ptxt
# Potencia por hierarquia (a sintaxe varia entre versoes; tenta duas formas)
if {[catch {report_power -hier all -hierarchical_depth 6 -file $out_dir/power_hier.rpt} e1]} {
    if {[catch {report_power -hierarchical_depth 6 -file $out_dir/power_hier.rpt} e2]} {
        puts "AVISO: nao consegui gerar power_hier.rpt: $e2"
        puts "       Veja 'report_power -help' nesta versao do Vivado."
    }
}

set pw_total "NA"; set pw_dyn "NA"; set pw_static "NA"; set pw_conf "NA"
regexp {Total On-Chip Power \(W\)\s*\|\s*([^\s|]+)} $ptxt -> pw_total
regexp {Dynamic \(W\)\s*\|\s*([^\s|]+)}             $ptxt -> pw_dyn
regexp {Device Static \(W\)\s*\|\s*([^\s|]+)}       $ptxt -> pw_static
regexp {Confidence Level\s*\|\s*([^\s|]+)}          $ptxt -> pw_conf

# ---------------- timing / Fmax do design ----------------
set clk    [lindex [get_clocks] 0]
set period [get_property PERIOD $clk]
set wns "NA"; set whs "NA"; set fmax "NA"
set sp [get_timing_paths -setup -max_paths 1]
set hp [get_timing_paths -hold  -max_paths 1]
if {[llength $sp]} { set wns [get_property SLACK [lindex $sp 0]] }
if {[llength $hp]} { set whs [get_property SLACK [lindex $hp 0]] }
if {$wns ne "NA" && ($period - $wns) > 0} {
    set fmax [format %.2f [expr {1000.0 / ($period - $wns)}]]
}

# ---------------- area do design (linha do top) ----------------
array set top [parse_util [report_utilization -return_string]]

set csv [list "modulo,instancia,LUT,FF,DSP,BRAM,pior_slack_ns"]
lappend csv "$top_name,(design inteiro),$top(lut),$top(ff),$top(dsp),$top(bram),$wns"

# ---------------- area / timing por modulo ----------------
set found 0
foreach c [get_cells -quiet -hierarchical -filter {IS_PRIMITIVE == 0}] {
    set ref [get_property REF_NAME $c]
    regsub {__parameterized[0-9]+$} $ref {} base
    if {[lsearch -exact $module_list $base] < 0} { continue }
    incr found

    set inst [get_property NAME $c]
    set utxt ""
    if {[catch {set utxt [report_utilization -cells $c -return_string]} err]} {
        puts "AVISO: report_utilization falhou para $inst: $err"
        continue
    }
    write_text "$out_dir/modules/[safe_name $inst]_util.rpt" $utxt
    array unset u
    array set u [parse_util $utxt]

    # pior slack setup dos caminhos que passam pelo modulo
    set slack "NA"
    set pins [get_pins -quiet -of_objects $c]
    if {[llength $pins]} {
        if {![catch {set p [get_timing_paths -quiet -setup -max_paths 1 -through $pins]}]} {
            if {[llength $p]} { set slack [get_property SLACK [lindex $p 0]] }
        }
    }
    lappend csv "$base,$inst,$u(lut),$u(ff),$u(dsp),$u(bram),$slack"
}
if {$found == 0} {
    puts "AVISO: nenhum modulo da module_list encontrado como celula hierarquica."
    puts "       A hierarquia foi achatada na sintese. Use flatten_hierarchy = none"
    puts "       (ou olhe util_hier.rpt) e rode de novo."
}

# ---------------- resumo ----------------
write_text $out_dir/summary_modules.csv [join $csv "\n"]

set sum [list \
    "design,$top_name" \
    "parte,$part" \
    "periodo_ns,$period" \
    "WNS_ns,$wns" \
    "WHS_ns,$whs" \
    "Fmax_MHz,$fmax" \
    "potencia_total_W,$pw_total" \
    "potencia_dinamica_W,$pw_dyn" \
    "potencia_estatica_W,$pw_static" \
    "confianca_potencia,$pw_conf" \
    "LUT,$top(lut)" "FF,$top(ff)" "DSP,$top(dsp)" "BRAM,$top(bram)"]
write_text $out_dir/summary_design.csv [join $sum "\n"]

puts ""
puts "=================== RESUMO ($top_name) ==================="
puts [join $sum "\n"]
puts "------------------- por modulo -------------------"
puts [join $csv "\n"]
puts "=========================================================="
puts "Arquivos em: [file normalize $out_dir]"
if {$saif_file eq ""} {
    puts "NOTA: potencia SEM SAIF e estimativa vectorless (confianca baixa)."
}