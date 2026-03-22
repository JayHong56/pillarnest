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
add wave -noupdate -color {Medium Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_x
add wave -noupdate -color {Medium Blue} -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/voxel_y
add wave -noupdate -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_x
add wave -noupdate -height 20 -radix unsigned /tb_voxelize/dut/voxel_coordinate_inst/u_hash_table_tombstone/key_y
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
add wave -noupdate /tb_voxelize/dut/u_pfe/serialize_busy
add wave -noupdate -radix unsigned -childformat {{{/tb_voxelize/dut/u_pfe/point_cnt[4]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/point_cnt[3]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/point_cnt[2]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/point_cnt[1]} -radix unsigned} {{/tb_voxelize/dut/u_pfe/point_cnt[0]} -radix unsigned}} -subitemconfig {{/tb_voxelize/dut/u_pfe/point_cnt[4]} {-height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/point_cnt[3]} {-height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/point_cnt[2]} {-height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/point_cnt[1]} {-height 15 -radix unsigned} {/tb_voxelize/dut/u_pfe/point_cnt[0]} {-height 15 -radix unsigned}} /tb_voxelize/dut/u_pfe/point_cnt
add wave -noupdate /tb_voxelize/dut/u_pfe/wr_ptr
add wave -noupdate /tb_voxelize/dut/u_pfe/rd_ptr
add wave -noupdate -radix unsigned /tb_voxelize/dut/u_pfe/ep_pnum
add wave -noupdate /tb_voxelize/dut/u_pfe/ep_valid
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 5} {30365000 ps} 1} {{Cursor 4} {30456668 ps} 0}
quietly wave cursor active 2
configure wave -namecolwidth 131
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
WaveRestoreZoom {30255798 ps} {30610760 ps}
bookmark add wave bookmark0 {{106113 ps} {197926 ps}} 0
