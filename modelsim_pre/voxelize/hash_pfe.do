onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/clk
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/rst_n
add wave -noupdate -color Gold -height 30 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/state
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/point_raw
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/s_fire
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/S_AXIS_DRAM_TDATA
add wave -noupdate -format Literal -height 30 /tb_voxelize/dut/voxel_coordinate_inst/S_AXIS_DRAM_TVALID
add wave -noupdate -format Literal -height 30 /tb_voxelize/dut/voxel_coordinate_inst/S_AXIS_DRAM_TREADY
add wave -noupdate -radix unsigned /tb_voxelize/dut/fifo_DRAM_2_axi_stream/o_bram_addr
add wave -noupdate -height 25 /tb_voxelize/dut/voxel_coordinate_inst/keep_point
add wave -noupdate -height 25 /tb_voxelize/dut/voxel_coordinate_inst/point_proc
add wave -noupdate -height 25 /tb_voxelize/dut/voxel_coordinate_inst/point_raw
add wave -noupdate -color Green -height 28 -radix binary /tb_voxelize/dut/voxel_coordinate_inst/float2fxp_x/float_in
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/pt_x_float32
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/pt_y_float32
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/pt_x_fix16
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/pt_y_fix16
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/fxp_add_x_out
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/fxp_mul_x_out
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/fxp_add_y_out
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/fxp_mul_y_out
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_y
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/seen_tombstone
add wave -noupdate -color Gold -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/state
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/out_idx
add wave -noupdate -color Coral -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/probe_count
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/point_number
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_y
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/r_data_raw
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/r_status
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/seen_tombstone
add wave -noupdate {/tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/mem[15]}
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/busy
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/mem
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/r_key_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/r_key_y
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/table_full
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/found
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/req_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/req_op
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/global_timer
add wave -noupdate -color Gold /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/temp_axis_expire_tready
add wave -noupdate -color Gold /tb_voxelize/dut/u_pfn/state
add wave -noupdate /tb_voxelize/dut/u_pfn/s_fire
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/bram_addr
add wave -noupdate /tb_voxelize/dut/u_pfn/bram_rdata
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/axis_voxel_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/axis_voxel_y
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/axis_bram_index
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/axis_point_num_indicator
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/r_point_num_indicator
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/r_bram_index
add wave -noupdate /tb_voxelize/dut/u_pfn/sum_x
add wave -noupdate /tb_voxelize/dut/u_pfn/sum_y
add wave -noupdate /tb_voxelize/dut/u_pfn/sum_z
add wave -noupdate /tb_voxelize/dut/u_pfn/mean_x
add wave -noupdate /tb_voxelize/dut/u_pfn/mean_y
add wave -noupdate /tb_voxelize/dut/u_pfn/mean_z
add wave -noupdate /tb_voxelize/dut/u_pfn/reciprocal_coeff
add wave -noupdate /tb_voxelize/dut/u_pfn/cnt_req
add wave -noupdate /tb_voxelize/dut/u_pfn/cnt_recv
add wave -noupdate /tb_voxelize/dut/u_pfn/cnt_point
add wave -noupdate /tb_voxelize/dut/u_pfn/r_rd_vld_pipe
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/last_row_points
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfn/need_read_rows
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
WaveRestoreCursors {{Cursor 1} {1300294 ps} 1} {{Cursor 2} {4609201 ps} 1} {{Cursor 3} {2701719 ps} 1} {{Cursor 4} {857855 ps} 1} {{Cursor 5} {6224248 ps} 1 Magenta default} {{Cursor 6} {33370366 ps} 0}
quietly wave cursor active 6
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
WaveRestoreZoom {32745323 ps} {34430464 ps}
bookmark add wave bookmark0 {{106113 ps} {197926 ps}} 0
