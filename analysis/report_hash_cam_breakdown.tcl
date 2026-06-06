set dcp_path {E:/verilog/board/vivado/kitti_2oc_32max/project_1.runs/impl_1/design_1_wrapper_routed.dcp}
set out_dir {E:/verilog/pillarnest/analysis/hash_cam_breakdown}
file mkdir $out_dir

open_checkpoint $dcp_path

set hash_cells [get_cells -hier -quiet -filter {NAME =~ *u_hash_table_tombstone*}]
if {[llength $hash_cells] > 0} {
    report_utilization -cells $hash_cells -file [file join $out_dir report_utilization_hash_table.rpt]
}

set cam_cells [get_cells -hier -quiet -filter {NAME =~ *u_hash_table_tombstone/cam_*}]
if {[llength $cam_cells] > 0} {
    report_utilization -cells $cam_cells -file [file join $out_dir report_utilization_cam_named_cells.rpt]
}

set cam_prim_csv [file join $out_dir cam_named_leaf_primitives.csv]
set fh [open $cam_prim_csv w]
puts $fh "name,ref_name,primitive_group"
foreach c [get_cells -hier -quiet -filter {NAME =~ *u_hash_table_tombstone/cam_* && IS_PRIMITIVE}] {
    puts $fh "\"$c\",[get_property REF_NAME $c],[get_property PRIMITIVE_GROUP $c]"
}
close $fh

set cam_related_cells [get_cells -hier -quiet -regexp {.*u_hash_table_tombstone/(cam_.*|cam_hit.*|cam_free.*|target_cam_idx.*|action_hit_cam.*)}]
if {[llength $cam_related_cells] > 0} {
    report_utilization -cells $cam_related_cells -file [file join $out_dir report_utilization_cam_related_cells.rpt]
}

set hash_prim_csv [file join $out_dir hash_table_leaf_primitives.csv]
set fh [open $hash_prim_csv w]
puts $fh "name,ref_name,primitive_group"
foreach c [get_cells -hier -quiet -filter {NAME =~ *u_hash_table_tombstone* && IS_PRIMITIVE}] {
    puts $fh "\"$c\",[get_property REF_NAME $c],[get_property PRIMITIVE_GROUP $c]"
}
close $fh

close_design
