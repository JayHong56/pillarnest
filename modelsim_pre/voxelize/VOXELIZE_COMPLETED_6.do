onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/clk
add wave -noupdate -height 30 /tb_voxelize/dut/voxel_coordinate_inst/rst_n
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pointcloud_dram/read_address
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
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/req_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s0_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_valid
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/busy
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/found
add wave -noupdate -height 20 /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/did_write
add wave -noupdate -color {Medium Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_x
add wave -noupdate -color {Medium Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_y
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/hash_stall
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/kill_write
add wave -noupdate -color Salmon -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/u_hash_expire_fifo_sync/level
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/hash_stall
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/hash_stall_counter
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/fifo_count
add wave -noupdate /tb_voxelize/dut/u_pfe/out_advance
add wave -noupdate -color Red -radix unsigned -childformat {{{/tb_voxelize/dut/u_pfe/point_cnt[4]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/point_cnt[3]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/point_cnt[2]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/point_cnt[1]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/point_cnt[0]} -radix unsigned}} -subitemconfig {{/tb_voxelize/dut/u_pfe/point_cnt[4]} {-color Red -height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/point_cnt[3]} {-color Red -height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/point_cnt[2]} {-color Red -height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/point_cnt[1]} {-color Red -height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/point_cnt[0]} {-color Red -height 15 -radix unsigned}} /tb_voxelize/dut/u_pfe/point_cnt
add wave -noupdate /tb_voxelize/dut/u_pfe/ep_fifo
add wave -noupdate /tb_voxelize/dut/u_pfe/m_axis_pfe_tready
add wave -noupdate /tb_voxelize/dut/u_pfe/m_axis_pfe_valid
add wave -noupdate /tb_voxelize/dut/u_pfe/m_axis_pfe_last
add wave -noupdate /tb_voxelize/dut/u_pfe/m_axis_pfe_voxel_valid
add wave -noupdate -radix unsigned -childformat {{{/tb_voxelize/dut/u_pfe/ep_fifo_pnum[0]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/ep_fifo_pnum[1]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/ep_fifo_pnum[2]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/ep_fifo_pnum[3]} -radix unsigned}} -subitemconfig {{/tb_voxelize/dut/u_pfe/ep_fifo_pnum[0]} {-height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/ep_fifo_pnum[1]} {-height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/ep_fifo_pnum[2]} {-height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/ep_fifo_pnum[3]} {-height 15 -radix unsigned}} /tb_voxelize/dut/u_pfe/ep_fifo_pnum
add wave -noupdate -color Gold /tb_voxelize/dut/u_pfe/fifo_rd_ptr
add wave -noupdate -color Gold /tb_voxelize/dut/u_pfe/fifo_wr_ptr
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
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/st4_pnum
add wave -noupdate /tb_voxelize/dut/u_pfe/st2_rd_valid
add wave -noupdate /tb_voxelize/dut/u_pfe/st2_to_st3
add wave -noupdate /tb_voxelize/dut/u_pfe/st2_phase
add wave -noupdate /tb_voxelize/dut/u_pfe/req_phase
add wave -noupdate /tb_voxelize/dut/u_pfe/req_valid
add wave -noupdate /tb_voxelize/dut/u_pfe/pipe_phase
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/st2_pnum
add wave -noupdate /tb_voxelize/dut/u_pfe/st2_point_data
add wave -noupdate /tb_voxelize/dut/u_pfe/fire_in
add wave -noupdate /tb_voxelize/dut/u_pfe/s_axis_expire_tdata
add wave -noupdate /tb_voxelize/dut/u_pfe/bram_pfe_rdata
add wave -noupdate -color Blue -radix unsigned /tb_voxelize/dut/u_pfe/bram_pfe_addr
add wave -noupdate -color Red -radix unsigned /tb_voxelize/dut/u_pfe/axis_bram_index
add wave -noupdate -format Literal /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_expire_manager/copy_st
add wave -noupdate /tb_voxelize/dut/u_pfe/pipe_stall
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pproc_d3
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_kill
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/hit_way
add wave -noupdate -radix unsigned {/tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/pn[3]}
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/a_addr_3
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/rdata3_a_eff
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/wdata3_b
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/shared_write_addr
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_free
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/action_full
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/probe_wait
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/is_probing
add wave -noupdate -color Blue /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/kill_write
add wave -noupdate -color Blue /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/kill_valid
add wave -noupdate -color Blue /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/kill_expired
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/hash_stall
add wave -noupdate -color Gold -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/global_timer
TreeUpdate [SetDefaultTree]
quietly WaveActivateNextPane
add wave -noupdate -color Gold /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/frame_end
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/flush_done
add wave -noupdate /tb_voxelize/dut/u_pfe/pfe_empty
add wave -noupdate /tb_voxelize/dut/u_pfe/m_axis_pfe_flush_done
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/did_write
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/point_raw_vld
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_y
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/pipe_stall
add wave -noupdate -color Red /tb_voxelize/dut/voxel_coordinate_inst/hash_fire
add wave -noupdate -color Red /tb_voxelize/dut/voxel_coordinate_inst/hash_req_ready
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/hash_req_ready_1delay
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/point_proc_comb
add wave -noupdate -color Blue -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/hash_out_idx
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/hash_out_point_number
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/test_reg
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/probe_offset
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/test_vector
add wave -noupdate -color Red /tb_voxelize/dut/voxel_coordinate_inst/pproc_d3
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pproc_d2
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pproc_d1
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/bram_voxelpoint_addr
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/bram_voxelpoint_bwen
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/bram_voxelpoint_wrdata
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/pproc_drop_d3
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/test_reg_voxel
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_x
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_valid
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/point_raw_vld
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/req_valid
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s1_y
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s0_x
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/s0_y
add wave -noupdate /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/cam_valid
add wave -noupdate -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/u_hash_load_monitor/total_load
TreeUpdate [SetDefaultTree]
quietly WaveActivateNextPane
add wave -noupdate -color Gray30 -radix unsigned /tb_voxelize/dut/m_axis_pfe_voxel_y
add wave -noupdate -color Gray30 -radix unsigned /tb_voxelize/dut/m_axis_pfe_voxel_x
add wave -noupdate -color Gray30 /tb_voxelize/dut/m_axis_pfe_voxel_valid
add wave -noupdate /tb_voxelize/dut/m_axis_pfe_valid
add wave -noupdate -color Red /tb_voxelize/dut/m_axis_pfe_tready
add wave -noupdate /tb_voxelize/dut/m_axis_pfe_last
add wave -noupdate /tb_voxelize/dut/m_axis_pfe_flush_done
add wave -noupdate /tb_voxelize/dut/m_axis_pfe_data
add wave -noupdate /tb_voxelize/dut/u_pfn_layer/pipe_ready
add wave -noupdate -divider -height 35 PFN
add wave -noupdate /tb_voxelize/dut/u_pfn_layer/st2_last
add wave -noupdate /tb_voxelize/dut/u_pfn_layer/st3_last
add wave -noupdate /tb_voxelize/dut/m_axis_pfn_flush_done
add wave -noupdate /tb_voxelize/dut/m_axis_pfn_data
add wave -noupdate -color Red /tb_voxelize/dut/m_axis_pfn_tready
add wave -noupdate /tb_voxelize/dut/m_axis_pfn_valid
add wave -noupdate -color Gray40 /tb_voxelize/dut/m_axis_pfn_voxel_valid
add wave -noupdate -color Gray40 -radix unsigned /tb_voxelize/dut/m_axis_pfn_voxel_y
add wave -noupdate -color Gray40 -radix unsigned /tb_voxelize/dut/m_axis_pfn_voxel_x
add wave -noupdate -divider -height 35 OUT
add wave -noupdate /tb_voxelize/dut/m_axis_out_tvalid
add wave -noupdate /tb_voxelize/dut/m_axis_out_tready
add wave -noupdate -color Red /tb_voxelize/dut/m_axis_out_tlast
add wave -noupdate /tb_voxelize/dut/m_axis_out_tdata
add wave -noupdate -divider -height 35 CMD
add wave -noupdate /tb_voxelize/dut/u_voxel_scatter_addr_gen/m_axis_cmd_tvalid
add wave -noupdate /tb_voxelize/dut/u_voxel_scatter_addr_gen/m_axis_cmd_tready
add wave -noupdate /tb_voxelize/dut/u_voxel_scatter_addr_gen/m_axis_cmd_tdata
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 5} {86008626 ps} 1} {{Cursor 7} {332343378 ps} 1} {{Cursor 8} {243677920 ps} 1} {{Cursor 7} {500755000 ps} 1} {{Cursor 5} {8529540 ps} 1} {{Cursor 6} {8529861 ps} 1} {{Cursor 7} {9959973 ps} 1} {{Cursor 8} {1201385 ps} 0}
quietly wave cursor active 8
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
WaveRestoreZoom {790480 ps} {959987 ps}
bookmark add wave bookmark0 {{106113 ps} {197926 ps}} 0
