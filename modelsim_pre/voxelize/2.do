onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/clk
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/rst_n
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/point_raw
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/s_fire
add wave -noupdate -color Gold -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/global_timer
add wave -noupdate -height 25 /tb_voxelize/dut/voxel_coordinate_inst/keep_point
add wave -noupdate -height 25 /tb_voxelize/dut/voxel_coordinate_inst/point_raw
add wave -noupdate -color Green -height 28 -radix binary /tb_voxelize/dut/voxel_coordinate_inst/float2fxp_x/float_in
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/pt_x_float32
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/pt_y_float32
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/pt_x_fix16
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/pt_y_fix16
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/fxp_mul_x_out
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/fxp_add_y_out
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/fxp_add_x_out
add wave -noupdate -color Green /tb_voxelize/dut/voxel_coordinate_inst/fxp_mul_y_out
add wave -noupdate -color {Medium Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_x
add wave -noupdate -color {Medium Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_y
add wave -noupdate -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_x
add wave -noupdate -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_y
add wave -noupdate -color {Orange Red} /tb_voxelize/dut/voxel_coordinate_inst/bram_wr
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/bram_addr
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pproc_vld_d1
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/req_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s0_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_valid
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/busy
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/found
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/did_write
add wave -noupdate -color {Medium Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_x
add wave -noupdate -color {Medium Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_y
add wave -noupdate -color {Slate Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/out_idx
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_func_0/hash_out
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_func_1/hash_out
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_func_2/hash_out
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_func_3/hash_out
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_bucket_0
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_bucket_1
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_bucket_2
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_bucket_3
add wave -noupdate -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/out_point_number
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/hit_way
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/wdata0_b
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/wdata1_b
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/wdata2_b
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/wdata3_b
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/st
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_load_monitor/bucket_load
add wave -noupdate -color Gold -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/global_timer
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/table_full
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/m_axis_expire_tvalid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/req_ready
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/req_valid
add wave -noupdate -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_x
add wave -noupdate -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_y
add wave -noupdate -color Gold -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s0_x
add wave -noupdate -color Gold -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s0_y
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/m_axis_expire_tdata
add wave -noupdate -color {Orange Red} -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_x
add wave -noupdate -color {Orange Red} -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_y
add wave -noupdate -color Gold -radix unsigned -radixshowbase 0 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/debug_s1_x
add wave -noupdate -color Gold -radix unsigned -radixshowbase 0 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/debug_s1_y
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/did_write
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/kill_expired
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/kill_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/kill_write
add wave -noupdate -color {Orange Red} /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/hit
add wave -noupdate -color {Orange Red} /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/free_found
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/rdata0_a_eff
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/rdata1_a_eff
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/rdata2_a_eff
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/rdata3_a_eff
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/shared_write_addr_bucket
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_bucket_0
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_bucket_1
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_bucket_2
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_bucket_3
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/bypass_en
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/bypass0
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/bypass1
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/bypass2
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/bypass3
add wave -noupdate -color {Slate Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/out_idx
add wave -noupdate -color Blue /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/expired
add wave -noupdate -color Turquoise /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_hit
add wave -noupdate -color Turquoise /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_free
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/rr_ptr
add wave -noupdate -radix binary /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/free_mask
add wave -noupdate -color {Medium Blue} /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_kill
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/did_write
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/out_idx
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/s1_time
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/r_ts
add wave -noupdate -color Gold -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/ts_reg
add wave -noupdate -color Blue /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/expired
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/s1_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/write_commit
add wave -noupdate -color Red -radix unsigned -radixshowbase 0 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/cand_addr
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/s0_addr
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/s1_addr
add wave -noupdate -radix unsigned -radixshowbase 0 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/dq_count
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/dq_wr_ptr
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/dq_rd_ptr
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_hit
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_free
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_kill
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_full
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/cand_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/a_rdata_shadow
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/a_addr_shadow
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/a_we_shadow
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/write_addr
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/wdata0_b
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/b_wdata
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/cycle_count
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/stall_cnt
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/r_status
add wave -noupdate -color Gold -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/global_timer
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/u_hash_expire_fifo_sync/level
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pointcloud_dram/read_address
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 14} {1375000 ps} 1} {{Cursor 5} {67368654 ps} 1} {{Cursor 5} {2100768 ps} 1} {{Cursor 5} {2063781 ps} 1} {{Cursor 5} {2055000 ps} 0}
quietly wave cursor active 5
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
WaveRestoreZoom {1956807 ps} {2122729 ps}
bookmark add wave bookmark0 {{106113 ps} {197926 ps}} 0
