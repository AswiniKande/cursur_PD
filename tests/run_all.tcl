#!/usr/bin/env tclsh
# Black-box tests for the practice fc_shell.

set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here ..]]
set shell [file join $root bin fc_shell]
cd $root

set failures 0
set passed 0

proc note {msg} {
  puts "  $msg"
}

proc check {name script} {
  global shell failures passed
  set tmp [file join /tmp fc_practice_test_[pid].tcl]
  set fh [open $tmp w]
  puts $fh $script
  close $fh
  set code [catch {exec $shell -no_log -f $tmp 2>@1} out]
  file delete -force $tmp
  if {$code} {
    incr failures
    puts "FAIL $name (exit)"
    puts $out
    return
  }
  if {![regexp {TEST_OK} $out]} {
    incr failures
    puts "FAIL $name"
    puts $out
    return
  }
  incr passed
  puts "PASS $name"
}

proc check_fail {name script pattern} {
  global shell failures passed
  set tmp [file join /tmp fc_practice_fail_[pid].tcl]
  set fh [open $tmp w]
  puts $fh $script
  close $fh
  set code [catch {exec $shell -no_log -f $tmp 2>@1} out]
  file delete -force $tmp
  if {$code == 0} {
    incr failures
    puts "FAIL $name (expected nonzero exit)"
    puts $out
    return
  }
  if {![regexp $pattern $out]} {
    incr failures
    puts "FAIL $name (pattern /$pattern/ not in output)"
    puts $out
    return
  }
  incr passed
  puts "PASS $name"
}

proc run_lab {n} {
  global shell root failures passed
  set sol [file join $root labs solutions [format lab%02d.tcl $n]]
  set script "practice_start $n\nsource {$sol}\nif {!\[practice_check\]} { exit 1 }\nputs TEST_OK\n"
  set tmp [file join /tmp fc_practice_lab_${n}_[pid].tcl]
  set fh [open $tmp w]
  puts $fh $script
  close $fh
  set code [catch {exec $shell -no_log -f $tmp 2>@1} out]
  file delete -force $tmp
  if {$code || ![regexp {LAB PASS} $out] || ![regexp {TEST_OK} $out]} {
    incr failures
    puts "FAIL lab $n"
    puts $out
    return
  }
  incr passed
  puts "PASS lab $n"
}

file delete -force [file join $root work]
file delete -force [file join $root reports]

set code [catch {exec $shell -version 2>@1} out]
if {$code == 0 && [string match *practice-1.0* $out]} {
  incr passed
  puts "PASS version flag"
} else {
  incr failures
  puts "FAIL version flag"
  puts $out
}

check basics {
  set_host_options -max_cores 4
  report_host_options
  set_app_options -name place.coarse.max_density -value 0.8
  if {[get_app_option -name place.coarse.max_density] != 0.8} { exit 1 }
  set x [expr {1 + 1}]
  if {$x != 2} { exit 1 }
  puts TEST_OK
}

check_fail unknown {
  not_a_command
} {unknown command 'not_a_command'}

check flow {
  set root $::fc::root
  set lib [file join $root work test_flow.ndm]
  create_lib -technology [file join $root designs practice_core tech.tf] \
    -ref_libs [file join $root designs practice_core std.celllib] $lib
  read_verilog -top practice_core [file join $root designs practice_core practice_core.v]
  link_block
  set leaves [sizeof_collection [get_cells -hierarchical -filter "is_hierarchical == false"]]
  set hiers [sizeof_collection [get_cells -hierarchical -filter "is_hierarchical == true"]]
  set seqs [sizeof_collection [all_registers]]
  set ports [sizeof_collection [get_ports]]
  set top [sizeof_collection [get_cells]]
  set rf [sizeof_collection [get_cells u_rf*/*]]
  set cks [sizeof_collection [get_pins -hierarchical -filter "name == CK"]]
  if {$leaves != 51 || $hiers != 11 || $seqs != 15 || $ports != 20 || $top != 18 || $rf != 16 || $cks != 15} {
    puts "counts leaves=$leaves hier=$hiers seq=$seqs ports=$ports top=$top rf=$rf ck=$cks"
    exit 1
  }
  set alu [get_attribute [get_cells u_alu] ref_name]
  if {$alu ne "alu4"} { puts "ref $alu"; exit 1 }
  set big [sizeof_collection [get_cells -hierarchical -filter "area >= 4.5 && is_sequential == true"]]
  if {$big != 15} { puts "big $big"; exit 1 }
  read_sdc [file join $root designs practice_core practice_core.sdc]
  if {[get_attribute [get_clocks clk] period] != 2.0} { exit 1 }
  set inputs [sizeof_collection [remove_from_collection [all_inputs] [get_ports clk]]]
  if {$inputs != 10} { puts "inputs $inputs"; exit 1 }
  initialize_floorplan -core_utilization 0.65 -side_ratio {1 1} -core_offset {10 10}
  place_pins -self
  create_placement -floorplan
  if {[check_floorplan] != 1} { exit 1 }
  set wns_place ""
  redirect -file [file join $root work qor_place.rpt] { report_qor }
  set fh [open [file join $root work qor_place.rpt] r]
  set txt [read $fh]
  close $fh
  if {![regexp {WNS \(ns\)\s+(-0\.180)} $txt]} { puts $txt; exit 1 }
  place_opt
  clock_opt
  route_auto
  route_opt
  redirect -file [file join $root work qor_final.rpt] { report_qor }
  set fh [open [file join $root work qor_final.rpt] r]
  set txt [read $fh]
  close $fh
  if {![regexp {WNS \(ns\)\s+(0\.040)} $txt]} { puts $txt; exit 1 }
  if {![regexp {route_opt} $txt]} { exit 1 }
  report_timing -max_paths 1
  set names [get_object_name [index_collection [sort_collection [get_cells] full_name] 0]]
  if {$names eq ""} { exit 1 }
  save_block
  save_lib
  close_lib
  open_lib $lib
  if {[sizeof_collection [get_cells -hierarchical -filter "is_hierarchical == false"]] != 51} { exit 1 }
  if {[get_flow_stage] ne "route_opt"} { puts [get_flow_stage]; exit 1 }
  puts TEST_OK
}

check collections {
  set root $::fc::root
  set lib [file join $root work test_col.ndm]
  create_lib -technology [file join $root designs practice_core tech.tf] \
    -ref_libs [file join $root designs practice_core std.celllib] $lib
  read_verilog -top practice_core [file join $root designs practice_core practice_core.v]
  link_block
  set pins [get_pins -of_objects [get_cells u_clkbuf]]
  if {[sizeof_collection $pins] < 2} { exit 1 }
  set nets [get_nets -of_objects [get_ports clk]]
  if {[get_object_name $nets] ne "clk"} { puts [get_object_name $nets]; exit 1 }
  set libs [get_lib_cells -filter "is_sequential == true"]
  if {[sizeof_collection $libs] != 2} { puts [get_object_name $libs]; exit 1 }
  set cmp [compare_collections [get_cells u_alu] [get_cells u_alu]]
  if {$cmp != 0} { exit 1 }
  set one [get_object_name [index_collection [get_cells u_rf*] 0]]
  if {![string match u_rf* $one]} { puts $one; exit 1 }
  foreach_in_collection c [get_cells u_alu] {
    set seen [get_object_name $c]
  }
  if {$seen ne "u_alu"} { exit 1 }
  puts TEST_OK
}

check_fail stage_order {
  set root $::fc::root
  set lib [file join $root work test_order.ndm]
  create_lib -technology [file join $root designs practice_core tech.tf] \
    -ref_libs [file join $root designs practice_core std.celllib] $lib
  read_verilog -top practice_core [file join $root designs practice_core practice_core.v]
  link_block
  place_opt
} {FLOW-001}

check redirect_and_filter {
  set root $::fc::root
  set lib [file join $root work test_redir.ndm]
  create_lib -technology [file join $root designs practice_core tech.tf] \
    -ref_libs [file join $root designs practice_core std.celllib] $lib
  read_verilog -top practice_core [file join $root designs practice_core practice_core.v]
  link_block
  set n [sizeof_collection [filter_collection [get_cells -hierarchical] "ref_name == DFFR && is_sequential == true"]]
  if {$n != 10} { puts "dffr $n"; exit 1 }
  set paren [sizeof_collection [get_cells -hierarchical -filter "(is_sequential == true) && (area > 4)"]]
  if {$paren != 15} { puts "paren $paren"; exit 1 }
  puts TEST_OK
}

# Logging is on unless -no_log is passed, and the log header calls `clock format`,
# which autoloads Tcl's package handler.
set code [catch {exec $shell -x {practice_labs} 2>@1} out]
file delete -force [file join $root fc_shell_command.log]
if {$code || ![regexp {Shell fundamentals} $out] || ![regexp {A flow procedure} $out]} {
  incr failures
  puts "FAIL practice_labs with command log"
  puts $out
} else {
  incr passed
  puts "PASS practice_labs with command log"
}

puts "labs:"
foreach n {1 2 3 4 5 6} {
  run_lab $n
}

# Multi-line continuation and stdin script.
set code [catch {exec $shell -no_log << {
practice_start 3
foreach_in_collection c [get_cells u_alu] {
  echo [get_object_name $c]
}
puts SEEN_$::practice::current
} 2>@1} out]
if {$code || ![string match {*u_alu*} $out] || ![string match {*SEEN_3*} $out]} {
  incr failures
  puts "FAIL stdin multiline"
  puts $out
} else {
  incr passed
  puts "PASS stdin multiline"
}

# Demo flow.
set code [catch {exec $shell -no_log -f [file join $root examples proto_flow.tcl] 2>@1} out]
if {$code || ![string match {*route_opt*} $out] || ![string match {*demo block saved*} $out]} {
  incr failures
  puts "FAIL demo flow"
  puts $out
} else {
  incr passed
  puts "PASS demo flow"
}

file delete -force [file join $root work]
file delete -force [file join $root reports]

puts "$passed passed, $failures failed"
if {$failures} { exit 1 }
exit 0
