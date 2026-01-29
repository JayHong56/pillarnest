onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/clk
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/rst_n
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/point_raw
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/s_fire
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/S_AXIS_DRAM_TDATA
add wave -noupdate -radix unsigned /tb_voxelize/dut/fifo_DRAM_2_axi_stream/o_bram_addr
add wave -noupdate -height 25 /tb_voxelize/dut/voxel_coordinate_inst/keep_point
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
add wave -noupdate -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_x
add wave -noupdate -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_y
add wave -noupdate -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_x
add wave -noupdate -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_y
add wave -noupdate -color {Orange Red} /tb_voxelize/dut/voxel_coordinate_inst/bram_wr
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/bram_addr
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/fifo_pop
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pproc_vld_d1
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/req_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s0_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_valid
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/busy
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/found
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/did_write
add wave -noupdate -height 20 -radix decimal /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/global_timer
add wave -noupdate -color {Slate Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/bucket_id
add wave -noupdate -color {Slate Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/out_idx
add wave -noupdate -height 20 -radix decimal /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/out_point_number
add wave -noupdate -color Blue -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/hit
add wave -noupdate -color Blue -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/free_found
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/hit_way
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/free_way
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/st
add wave -noupdate -color Red -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/a_addr
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_valid
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/fifo_level
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/table_full
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/m_axis_expire_tvalid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/m_axis_expire_tdata
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/s1_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/s0_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/expired
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/b_rdata
add wave -noupdate -radix unsigned -radixshowbase 0 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/b_addr
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/cand_valid
add wave -noupdate -radix unsigned -radixshowbase 0 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/cand_addr
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_y
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_bucket
add wave -noupdate {/tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_bucket_bram3/mem[4]}
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/rdata0_a
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/rdata1_a
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/rdata2_a
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/rdata3_a
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/wdata0_a
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/wdata1_a
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/wdata2_a
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/wdata3_a
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 6} {314709 ps} 1} {{Cursor 8} {345000 ps} 1} {{Cursor 9} {174966 ps} 1} {{Cursor 10} {1179612 ps} 1} {{Cursor 5} {204839 ps} 0}
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
WaveRestoreZoom {127145 ps} {410782 ps}
bookmark add wave bookmark0 {{106113 ps} {197926 ps}} 0
