onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/clk
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/rst_n
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/point_raw
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/s_fire
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/fifo_in_valid
add wave -noupdate -color Blue /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/expired
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/r_point_num_indicator
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/r_bram_index
add wave -noupdate /tb_voxelize/dut/u_pfn/cnt_req
add wave -noupdate /tb_voxelize/dut/u_pfn/cnt_recv
add wave -noupdate /tb_voxelize/dut/u_pfn/cnt_point
add wave -noupdate /tb_voxelize/dut/u_pfn/r_rd_vld_pipe
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/last_row_points
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/need_read_rows
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/global_timer
add wave -noupdate -color Gold /tb_voxelize/dut/u_pfn/state
add wave -noupdate /tb_voxelize/dut/u_pfn/s_fire
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/bram_addr
add wave -noupdate /tb_voxelize/dut/u_pfn/bram_rdata
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/axis_voxel_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/axis_voxel_y
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/axis_bram_index
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/axis_point_num_indicator
add wave -noupdate /tb_voxelize/dut/u_pfn/sum_x
add wave -noupdate /tb_voxelize/dut/u_pfn/sum_y
add wave -noupdate /tb_voxelize/dut/u_pfn/sum_z
add wave -noupdate /tb_voxelize/dut/u_pfn/mean_x
add wave -noupdate /tb_voxelize/dut/u_pfn/mean_y
add wave -noupdate /tb_voxelize/dut/u_pfn/mean_z
add wave -noupdate /tb_voxelize/dut/u_pfn/reciprocal_coeff
add wave -noupdate /tb_voxelize/dut/u_pfn/expanded_points_buffer
add wave -noupdate /tb_voxelize/dut/u_pfn/points_buffer
add wave -noupdate /tb_voxelize/dut/u_pfn/temp_mult_x
add wave -noupdate /tb_voxelize/dut/u_pfn/temp_mult_y
add wave -noupdate /tb_voxelize/dut/u_pfn/temp_mult_z
add wave -noupdate /tb_voxelize/dut/u_pfn/temp_mult_voxel_x
add wave -noupdate /tb_voxelize/dut/u_pfn/temp_mult_voxel_y
add wave -noupdate /tb_voxelize/dut/u_pfn/temp_sub_voxel_x
add wave -noupdate /tb_voxelize/dut/u_pfn/temp_sub_voxel_y
add wave -noupdate /tb_voxelize/dut/u_pfn/voxel_x_fix16
add wave -noupdate /tb_voxelize/dut/u_pfn/voxel_y_fix16
add wave -noupdate /tb_voxelize/dut/u_pfn/voxel_z_fix16
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1300294 ps} 1} {{Cursor 6} {1440491 ps} 0}
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
WaveRestoreZoom {1403032 ps} {1535344 ps}
bookmark add wave bookmark0 {{106113 ps} {197926 ps}} 0
