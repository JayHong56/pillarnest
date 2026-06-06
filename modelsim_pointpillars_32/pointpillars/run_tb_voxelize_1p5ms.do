onbreak {quit -f}
onerror {quit -code 1}

if {[info exists ::env(MODELSIM_POINTPILLARS_ROOT)]} {
    set project_root [file normalize $::env(MODELSIM_POINTPILLARS_ROOT)]
} else {
    set project_root [pwd]
}
set log_dir [file join $project_root logs]
file mkdir $log_dir

set stamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
transcript file [file join $log_dir "tb_voxelize_1p5ms_$stamp.log"]

echo "Running work.tb_voxelize for 1.5 ms"
catch {quit -sim}
vsim work.tb_voxelize
run 1.5 ms
quit -f
