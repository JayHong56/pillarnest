set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set rtl_dir [file join $repo_dir temp rtl voxelize_kitti_codex_opt]
set proj_dir [file join $script_dir project]
set rpt_dir [file join $script_dir reports]

file mkdir $proj_dir
file mkdir $rpt_dir

# Change this part if your target board is different.
set part_name xc7z020clg400-1

create_project -force pointpillars_codex_opt $proj_dir -part $part_name
set rtl_files [glob -nocomplain [file join $rtl_dir *.v]]
if {[llength $rtl_files] == 0} {
    error "No RTL files found under $rtl_dir"
}

add_files -norecurse $rtl_files
set_property top voxelize_core_synth_top [current_fileset]
update_compile_order -fileset sources_1

synth_design -top voxelize_core_synth_top -part $part_name -mode out_of_context

# The datapath uses clk with a 5 ns period here.  This gives a useful first
# timing target for the optimized RTL; adjust to your real platform clock.
create_clock -name clk -period 5.000 [get_ports clk]

report_utilization -file [file join $rpt_dir utilization_synth.rpt]
report_timing_summary -file [file join $rpt_dir timing_summary_synth.rpt]
report_utilization -hierarchical -hierarchical_depth 3 -file [file join $rpt_dir utilization_hier_synth.rpt]
report_design_analysis -timing -file [file join $rpt_dir design_analysis_timing.rpt]

write_checkpoint -force [file join $rpt_dir voxelize_core_synth_top_synth.dcp]
