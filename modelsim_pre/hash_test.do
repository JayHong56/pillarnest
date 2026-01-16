onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_dram/clk
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/rst_n
add wave -noupdate -radix unsigned /tb_voxelize/dut/dram_fifo/o_bram_addr
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
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/seen_tombstone
add wave -noupdate -color Gold -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/state
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/probe_count
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_y
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/r_data_raw
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/r_status
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/seen_tombstone
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/busy
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/out_idx
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/mem
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/r_key_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/r_key_y
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/temp
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/temp_crush
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/table_full
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/found
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/req_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/req_op
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1300294 ps} 1} {{Cursor 2} {142998497 ps} 0}
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
WaveRestoreZoom {142020058 ps} {143051576 ps}
bookmark add wave bookmark0 {{106113 ps} {197926 ps}} 0
