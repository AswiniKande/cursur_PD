# Full practice flow for practice_core. Safe to run more than once.
set root $::fc::root
set libpath [file join $root work demo.ndm]
if {[::fc::has_lib]} {
  close_lib -force
}
if {[file exists $libpath]} {
  file delete -force $libpath
}
set_host_options -max_cores 4
create_lib \
  -technology [file join $root designs practice_core tech.tf] \
  -ref_libs [file join $root designs practice_core std.celllib] \
  $libpath
read_verilog -top practice_core [file join $root designs practice_core practice_core.v]
link_block
read_sdc [file join $root designs practice_core practice_core.sdc]
report_design
initialize_floorplan -core_utilization 0.65 -side_ratio {1 1} -core_offset {10 10}
place_pins -self
create_placement_blockage -name keepout -bbox {0 0 4 4}
create_placement -floorplan
check_floorplan
create_net -power VDD
create_net -ground VSS
connect_pg_net -net VDD [get_pins -hierarchical -filter "name == VDD"]
connect_pg_net -net VSS [get_pins -hierarchical -filter "name == VSS"]
compile_fusion
report_qor
report_timing -max_paths 2
save_block
save_lib
echo "demo block saved at $libpath"
