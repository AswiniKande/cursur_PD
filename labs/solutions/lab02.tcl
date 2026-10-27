set root $::fc::root
set libpath [file join $root work practice.ndm]
if {[::fc::has_lib]} {
  close_lib -force
}
if {[file exists $libpath]} {
  file delete -force $libpath
}
create_lib \
  -technology [file join $root designs practice_core tech.tf] \
  -ref_libs [file join $root designs practice_core std.celllib] \
  $libpath
read_verilog -top practice_core [file join $root designs practice_core practice_core.v]
link_block
read_sdc [file join $root designs practice_core practice_core.sdc]
save_block
save_lib
