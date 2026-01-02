onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_dram/clk
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/rst_n
add wave -noupdate -radix unsigned /tb_voxelize/dut/dram_fifo/o_bram_addr
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/out_idx
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/seen_tombstone
add wave -noupdate -color Gold -height 30 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/state
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/point_raw
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/s_fire
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/S_AXIS_DRAM_TDATA
add wave -noupdate -format Literal -height 30 /tb_voxelize/dut/voxel_coordinate_inst/S_AXIS_DRAM_TVALID
add wave -noupdate -format Literal -height 30 /tb_voxelize/dut/voxel_coordinate_inst/S_AXIS_DRAM_TREADY
add wave -noupdate -height 25 /tb_voxelize/dut/voxel_coordinate_inst/keep_point
add wave -noupdate -height 25 /tb_voxelize/dut/voxel_coordinate_inst/point_proc
add wave -noupdate -height 25 /tb_voxelize/dut/voxel_coordinate_inst/point_raw
add wave -noupdate /tb_voxelize/dut/voxel_dram/en
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/ABS_pt_x_int16
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/ABS_pt_y_int16
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/ABS_pt_z_int16
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pt_x_int16
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pt_y_int16
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pt_z_int16
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/point_cloud_x
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/point_cloud_y
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/point_cloud_z
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/point_cloud_i
add wave -noupdate -color Green -height 28 -radix binary /tb_voxelize/dut/voxel_coordinate_inst/float2fxp_x/float_in
add wave -noupdate -color Green -height 28 /tb_voxelize/dut/voxel_coordinate_inst/float2fxp_x/fixed_sign
add wave -noupdate -color Green -height 28 /tb_voxelize/dut/voxel_coordinate_inst/float2fxp_x/true_fixed_value
add wave -noupdate -color Green -height 28 /tb_voxelize/dut/voxel_coordinate_inst/float2fxp_x/float_exp
add wave -noupdate -color Green -height 28 /tb_voxelize/dut/voxel_coordinate_inst/float2fxp_x/float_mantissa
add wave -noupdate -color Green -height 28 /tb_voxelize/dut/voxel_coordinate_inst/float2fxp_x/working_out
add wave -noupdate -color Green -height 28 /tb_voxelize/dut/voxel_coordinate_inst/float2fxp_x/shift_dist
add wave -noupdate -color Green -height 28 -radix decimal /tb_voxelize/dut/voxel_coordinate_inst/float2fxp_x/trunc_shift_dist
add wave -noupdate -color Green -height 28 -radix binary /tb_voxelize/dut/voxel_coordinate_inst/float2fxp_x/shifted_out
add wave -noupdate -color Green -height 28 /tb_voxelize/dut/voxel_coordinate_inst/float2fxp_x/fixed_mag
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {175000 ps} 0} {{Cursor 2} {62925000 ps} 0}
quietly wave cursor active 2
configure wave -namecolwidth 178
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits us
update
WaveRestoreZoom {62690497 ps} {63319504 ps}
bookmark add wave bookmark3 {{106113 ps} {197926 ps}} 0
