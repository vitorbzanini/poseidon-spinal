cat > run_project2.tcl <<'EOF'
proc env_or {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $default
}

set xpr  [env_or XPR  ./project_2.xpr]
set part [env_or PART ""]
set jobs [env_or JOBS 4]

puts "VIVADO : [version -short]"
if {![file exists $xpr]} { error "Projeto nao encontrado: $xpr" }

open_project $xpr
puts "PART atual: [get_property part [current_project]]"

if {$part ne ""} {
    set_property part $part [current_project]
    puts "PART alterado para $part"
}

set out_dir [file join [get_property directory [current_project]] reports]
file mkdir $out_dir

# sintese
reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Sintese falhou: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1 -name synth_1
report_utilization    -file $out_dir/synth_utilization.rpt
report_timing_summary -file $out_dir/synth_timing.rpt -max_paths 10
close_design

# implementacao
reset_run impl_1
launch_runs impl_1 -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementacao falhou: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1 -name impl_1
report_utilization    -file $out_dir/route_utilization.rpt
report_utilization    -hierarchical -file $out_dir/route_utilization_hier.rpt
report_timing_summary -file $out_dir/route_timing.rpt -max_paths 10
report_power          -file $out_dir/route_power.rpt
report_drc            -file $out_dir/route_drc.rpt

puts "FIM. Relatorios em $out_dir"
close_project
EOF