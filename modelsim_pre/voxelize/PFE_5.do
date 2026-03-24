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
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/point_proc_comb
add wave -noupdate -color {Medium Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_x
add wave -noupdate -color {Medium Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_y
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pt_z_fix16
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pt_y_fix16
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pt_x_fix16
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
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/kill_write
add wave -noupdate -color Salmon -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/u_hash_expire_fifo_sync/level
add wave -noupdate -color Salmon /tb_voxelize/dut/u_pfe/serialize_busy
add wave -noupdate -color Red -radix unsigned -childformat {{{/tb_voxelize/dut/u_pfe/point_cnt[4]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/point_cnt[3]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/point_cnt[2]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/point_cnt[1]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/point_cnt[0]} -radix unsigned}} -subitemconfig {{/tb_voxelize/dut/u_pfe/point_cnt[4]} {-color Red -height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/point_cnt[3]} {-color Red -height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/point_cnt[2]} {-color Red -height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/point_cnt[1]} {-color Red -height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/point_cnt[0]} {-color Red -height 15 -radix unsigned}} /tb_voxelize/dut/u_pfe/point_cnt
add wave -noupdate /tb_voxelize/dut/u_pfe/m_axis_pfe_last
add wave -noupdate /tb_voxelize/dut/u_pfe/m_axis_pfe_voxel_valid
add wave -noupdate -radix unsigned -childformat {{{/tb_voxelize/dut/u_pfe/ep_fifo_pnum[0]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/ep_fifo_pnum[1]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/ep_fifo_pnum[2]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/ep_fifo_pnum[3]} -radix unsigned}} -subitemconfig {{/tb_voxelize/dut/u_pfe/ep_fifo_pnum[0]} {-height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/ep_fifo_pnum[1]} {-height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/ep_fifo_pnum[2]} {-height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/ep_fifo_pnum[3]} {-height 15 -radix unsigned}} /tb_voxelize/dut/u_pfe/ep_fifo_pnum
add wave -noupdate -color Gold /tb_voxelize/dut/u_pfe/fifo_rd_ptr
add wave -noupdate -color Gold /tb_voxelize/dut/u_pfe/fifo_wr_ptr
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/fifo_count
add wave -noupdate /tb_voxelize/dut/u_pfe/voxel_pop
add wave -noupdate /tb_voxelize/dut/u_pfe/m_axis_pfe_data
add wave -noupdate /tb_voxelize/dut/u_pfe/fifo_empty
add wave -noupdate /tb_voxelize/dut/u_pfe/fifo_full
add wave -noupdate /tb_voxelize/dut/u_pfe/st4_push
add wave -noupdate /tb_voxelize/dut/u_pfe/st4_valid
add wave -noupdate /tb_voxelize/dut/u_pfe/st3_valid
add wave -noupdate /tb_voxelize/dut/u_pfe/st2_valid
add wave -noupdate /tb_voxelize/dut/u_pfe/st2_to_st3
add wave -noupdate /tb_voxelize/dut/u_pfe/st4_points_buffer
add wave -noupdate /tb_voxelize/dut/u_pfe/st3_points_buffer
add wave -noupdate /tb_voxelize/dut/u_pfe/st2_points_buffer
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/base_idx
add wave -noupdate /tb_voxelize/dut/u_pfe/cur_last_fire
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/st4_pnum
add wave -noupdate /tb_voxelize/dut/u_pfe/st2_rd_valid
add wave -noupdate /tb_voxelize/dut/u_pfe/st2_phase
add wave -noupdate /tb_voxelize/dut/u_pfe/req_phase
add wave -noupdate /tb_voxelize/dut/u_pfe/req_valid
add wave -noupdate /tb_voxelize/dut/u_pfe/pipe_phase
add wave -noupdate /tb_voxelize/dut/u_pfe/st2_pnum
add wave -noupdate /tb_voxelize/dut/u_pfe/st2_point_data
add wave -noupdate /tb_voxelize/dut/u_pfe/fire_in
add wave -noupdate /tb_voxelize/dut/u_pfe/s_axis_expire_tdata
add wave -noupdate -color Blue /tb_voxelize/dut/u_pfe/bram_pfe_rdata
add wave -noupdate -color Blue -radix unsigned /tb_voxelize/dut/u_pfe/bram_pfe_addr
add wave -noupdate -color Red -radix unsigned /tb_voxelize/dut/u_pfe/axis_bram_index
add wave -noupdate -format Literal /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/copy_st
add wave -noupdate /tb_voxelize/dut/u_pfe/pipe_stall
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pproc_d3
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_kill
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_hit
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_free
TreeUpdate [SetDefaultTree]
quietly WaveActivateNextPane
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/bram_expire_addr_b
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/bram_expire_wrdata_b
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/bram_expire_rdata_a
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/expired
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/s1_addr
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/st4_voxel_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/st4_voxel_y
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/axis_voxel_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/axis_voxel_y
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/m_axis_expire_tvalid
add wave -noupdate -format Literal /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/copy_st
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/bram_b_wr_ptr
add wave -noupdate -color Red -radix unsigned /tb_voxelize/dut/u_pfe/axis_bram_index
add wave -noupdate -color Gold -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/global_timer
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/task_empty
TreeUpdate [SetDefaultTree]
quietly WaveActivateNextPane
add wave -noupdate /tb_voxelize/dut/u_pfe/m_axis_pfe_voxel_valid
add wave -noupdate /tb_voxelize/dut/u_pfe/m_axis_pfe_last
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/axis_voxel_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/axis_voxel_y
add wave -noupdate /tb_voxelize/dut/u_pfe/bram_pfe_rdata
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/axis_bram_index
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/bram_expire_addr_b
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/bram_expire_bwen_b
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/bram_expire_wr_b
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/bram_expire_wrdata_b
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/bram_expire_rdata_a
add wave -noupdate -color Red -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/bram_expire_addr_a
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/fifo_out_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/fifo_out_ready
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/s0_addr
add wave -noupdate {/tb_voxelize/dut/u_pfe_bram/mem_2delay[6]}
add wave -noupdate {/tb_voxelize/dut/u_pfe_bram/mem_2delay[5]}
add wave -noupdate {/tb_voxelize/dut/u_pfe_bram/mem_2delay[4]}
add wave -noupdate {/tb_voxelize/dut/u_pfe_bram/mem_2delay[3]}
add wave -noupdate {/tb_voxelize/dut/u_pfe_bram/mem_2delay[2]}
add wave -noupdate {/tb_voxelize/dut/u_pfe_bram/mem_2delay[1]}
add wave -noupdate {/tb_voxelize/dut/u_pfe_bram/mem_2delay[0]}
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 9} {2053518 ps} 1} {{Cursor 12} {1455000 ps} 1} {{Cursor 9} {1982484 ps} 1} {{Cursor 10} {1983609 ps} 0}
quietly wave cursor active 4
configure wave -namecolwidth 173
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
WaveRestoreZoom {24114 ps} {164297 ps}
bookmark add wave bookmark0 {{106113 ps} {197926 ps}} 0
