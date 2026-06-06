set dcp_path {E:/verilog/board/vivado/kitti_2oc_32max/project_1.runs/impl_1/design_1_wrapper_routed.dcp}
set out_dir {E:/verilog/pillarnest/analysis/pfn_lut_breakdown}
file mkdir $out_dir

open_checkpoint $dcp_path

set hier_rpt [file join $out_dir report_utilization_hierarchical.rpt]
report_utilization -hierarchical -hierarchical_depth 20 -file $hier_rpt

set pfn_cells [get_cells -hier -quiet -filter {NAME =~ *u_pfn_layer*}]
set pfn_util_rpt [file join $out_dir report_utilization_pfn_cells.rpt]
if {[llength $pfn_cells] > 0} {
    report_utilization -cells $pfn_cells -file $pfn_util_rpt
}

set cell_csv [file join $out_dir pfn_leaf_cells.csv]
set fh [open $cell_csv w]
puts $fh "name,ref_name,primitive_group"
foreach c [get_cells -hier -quiet -filter {NAME =~ *u_pfn_layer* && IS_PRIMITIVE}] {
    set ref [get_property REF_NAME $c]
    set pg [get_property PRIMITIVE_GROUP $c]
    puts $fh "\"$c\",$ref,$pg"
}
close $fh

set lut_csv [file join $out_dir pfn_lut_cells.csv]
set fh [open $lut_csv w]
puts $fh "name,ref_name"
foreach c [get_cells -hier -quiet -filter {NAME =~ *u_pfn_layer* && IS_PRIMITIVE && REF_NAME =~ LUT*}] {
    set ref [get_property REF_NAME $c]
    puts $fh "\"$c\",$ref"
}
close $fh

set dsp_csv [file join $out_dir pfn_dsp_cells.csv]
set fh [open $dsp_csv w]
puts $fh "name,ref_name"
foreach c [get_cells -hier -quiet -filter {NAME =~ *u_pfn_layer* && IS_PRIMITIVE && REF_NAME =~ DSP*}] {
    set ref [get_property REF_NAME $c]
    puts $fh "\"$c\",$ref"
}
close $fh

close_design
