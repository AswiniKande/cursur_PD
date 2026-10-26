# Guided labs. Checks look at shell state after you type the commands.

namespace eval ::practice {
  variable current 0
  variable labs [dict create]
}

proc ::practice::add {number title intro tasks} {
  variable labs
  dict set labs $number [dict create title $title intro $intro tasks $tasks]
}

proc ::practice::task {id title hint check} {
  return [dict create id $id title $title hint $hint check $check]
}

proc ::practice::load_design {stage} {
  set root $::fc::root
  set path [file join $root work lab_session.ndm]
  if {[::fc::has_lib]} {
    close_lib -force
  }
  if {[file exists $path]} {
    file delete -force $path
  }
  create_lib \
    -technology [file join $root designs practice_core tech.tf] \
    -ref_libs [file join $root designs practice_core std.celllib] \
    $path
  read_verilog -top practice_core [file join $root designs practice_core practice_core.v]
  link_block
  read_sdc [file join $root designs practice_core practice_core.sdc]
  if {$stage eq "floorplanned" || $stage eq "placed"} {
    initialize_floorplan -core_utilization 0.60 -side_ratio {1 1} -core_offset {8 8}
  }
  if {$stage eq "placed"} {
    place_pins -self
    create_placement -floorplan
  }
}

proc ::practice::init {} {
  ::practice::add 1 "Shell fundamentals" \
    "Plain Tcl, inside the shell. No design is required.\nChecked names: design_name, target_util, mods, and proc banner." \
    [list \
      [::practice::task name "Set design_name to practice_core" \
        "set design_name practice_core" \
        { if {![info exists ::design_name]} { return 0 }; expr {$::design_name eq "practice_core"} }] \
      [::practice::task util "Set target_util to 0.7" \
        "set target_util 0.7" \
        { if {![info exists ::target_util]} { return 0 }; expr {abs($::target_util - 0.7) < 1e-9} }] \
      [::practice::task mods "Set mods to the module list alu4 regbit decoder control" \
        "set mods {alu4 regbit decoder control}" \
        { if {![info exists ::mods]} { return 0 }; expr {$::mods eq {alu4 regbit decoder control}} }] \
      [::practice::task banner "Define proc banner that returns practice_core util=0.70" \
        "proc banner {} { return \"\$::design_name util=\[format %.2f \$::target_util\]\" }" \
        { if {[info procs banner] eq ""} { return 0 }; expr {[banner] eq "practice_core util=0.70"} }]]

  ::practice::add 2 "Build a block" \
    "Create work/practice.ndm from the practice_core kit, link it, read the SDC, and save.\nPaths are under $::fc::root (the repo root), not the shell's imagination.\nIf create_lib says the library exists, delete work/practice.ndm and try again." \
    [list \
      [::practice::task lib "create_lib work/practice.ndm with the kit technology and cell library" \
        "create_lib -technology \$root/designs/practice_core/tech.tf -ref_libs \$root/designs/practice_core/std.celllib \$root/work/practice.ndm" \
        { set p [file join $::fc::root work practice.ndm]; expr {[file isdirectory $p] && [::fc::has_lib] && [::fc::current_lib_name] eq "practice"} }] \
      [::practice::task link "read_verilog -top practice_core and link_block" \
        "read_verilog -top practice_core \$root/designs/practice_core/practice_core.v\nlink_block" \
        { if {![::fc::has_block]} { return 0 }; set b [::fc::block_get]; expr {[dict get $b name] eq "practice_core" && [dict get $b linked]} }] \
      [::practice::task sdc "read_sdc so clock clk has period 2.0" \
        "read_sdc \$root/designs/practice_core/practice_core.sdc" \
        { set c [get_clocks -quiet clk]; if {[sizeof_collection $c] != 1} { return 0 }; expr {[get_attribute $c period] == 2.0} }] \
      [::practice::task save "save_block and save_lib" \
        "save_block\nsave_lib" \
        { expr {[file exists [file join $::fc::root work practice.ndm practice_core.block]] && [file exists [file join $::fc::root work practice.ndm lib.info]]} }]]

  ::practice::add 3 "Collections" \
    "The lab design is already linked. * does not cross '/'.\n-hierarchical with no slash matches the leaf name at every level.\nLoop variables from foreach_in_collection are collections; use get_attribute or get_object_name." \
    [list \
      [::practice::task nleaves "Set nleaves to the number of leaf cells" \
        "set nleaves \[sizeof_collection \[get_cells -hierarchical -filter \"is_hierarchical == false\"\]\]" \
        { if {![info exists ::nleaves]} { return 0 }
          set truth [sizeof_collection [get_cells -hierarchical -filter "is_hierarchical == false"]]
          expr {$::nleaves == $truth} }] \
      [::practice::task seq "Set seq_names to the sorted full names of all registers" \
        "set seq_names \[lsort \[get_object_name \[all_registers\]\]\]" \
        { if {![info exists ::seq_names]} { return 0 }
          set truth [lsort [get_object_name [all_registers]]]
          expr {$::seq_names eq $truth} }] \
      [::practice::task rf "Set rf_cells to the sorted full names of cells matching u_rf*/*" \
        "set rf_cells \[lsort \[get_object_name \[get_cells u_rf*/*\]\]\]" \
        { if {![info exists ::rf_cells]} { return 0 }
          set truth [lsort [get_object_name [get_cells u_rf*/*]]]
          expr {$::rf_cells eq $truth} }] \
      [::practice::task ck "Set clk_pins to the number of pins named CK" \
        "set clk_pins \[sizeof_collection \[get_pins -hierarchical -filter \"name == CK\"\]\]" \
        { if {![info exists ::clk_pins]} { return 0 }
          set truth [sizeof_collection [get_pins -hierarchical -filter "name == CK"]]
          expr {$::clk_pins == $truth} }]]

  ::practice::add 4 "Attributes and reports" \
    "Still on the linked lab design. dont_touch is a real attribute. practice_tag is one you invent." \
    [list \
      [::practice::task touch "set_dont_touch on hierarchical cell u_ctrl" \
        "set_dont_touch \[get_cells u_ctrl\] true" \
        { set c [get_cells -quiet u_ctrl]
          if {[sizeof_collection $c] != 1} { return 0 }
          expr {[get_attribute $c dont_touch] eq "true"} }] \
      [::practice::task tag "Set practice_tag lab4 on every register" \
        "foreach_in_collection r \[all_registers\] { set_attribute \$r practice_tag lab4 }" \
        { set ok 1
          foreach_in_collection r [all_registers] {
            if {[get_attribute $r practice_tag] ne "lab4"} { set ok 0 }
          }
          return $ok }] \
      [::practice::task rpt "redirect report_qor to reports/qor_lab4.rpt" \
        "redirect -file reports/qor_lab4.rpt { report_qor }" \
        { if {![file exists reports/qor_lab4.rpt]} { return 0 }
          set fh [open reports/qor_lab4.rpt r]
          set txt [read $fh]
          close $fh
          expr {[string match *practice_core* $txt] && [string match *WNS* $txt]} }]]

  ::practice::add 5 "Floorplan" \
    "Start from the linked design. Target utilization 0.65, side ratio 1 1, core offset 10 10.\nThen place ports, create a floorplan placement, and add a placement blockage." \
    [list \
      [::practice::task init "initialize_floorplan with utilization 0.65, ratio {1 1}, offset {10 10}" \
        "initialize_floorplan -core_utilization 0.65 -side_ratio {1 1} -core_offset {10 10}" \
        { if {[::fc::floorplan_get util_target] eq ""} { return 0 }
          expr {abs([::fc::floorplan_get util_target] - 0.65) < 1e-9 && [::fc::floorplan_get side_ratio] eq {1 1} && [::fc::floorplan_get core_offset] eq {10 10}} }] \
      [::practice::task pins "place_pins -self" \
        "place_pins -self" \
        { expr {[::fc::floorplan_get pins_placed] eq 1 || [::fc::floorplan_get pins_placed] eq "1"} }] \
      [::practice::task place "create_placement -floorplan" \
        "create_placement -floorplan" \
        { expr {[::fc::stage_index [get_flow_stage]] >= [::fc::stage_index placed]} }] \
      [::practice::task blk "create a placement blockage" \
        "create_placement_blockage -name keepout -bbox {0 0 5 5}" \
        { expr {[llength [::fc::floorplan_get blockages]] >= 1} }] \
      [::practice::task check "floorplan check passes" \
        "check_floorplan" \
        { expr {[check_floorplan] == 1} }]]

  ::practice::add 6 "A flow procedure" \
    "Write proc implement_proto {} for the block that is already open.\nIt must initialize_floorplan at utilization 0.60 with side ratio {1 1} and offset {8 8},\nplace_pins -self, create_placement -floorplan, place_opt, and save_block.\npractice_check reloads a fresh linked block and calls your proc." \
    [list \
      [::practice::task proto "proc implement_proto runs the proto flow and save_block" \
        "proc implement_proto {} {\n  initialize_floorplan -core_utilization 0.60 -side_ratio {1 1} -core_offset {8 8}\n  place_pins -self\n  create_placement -floorplan\n  place_opt\n  save_block\n}" \
        { if {[info procs implement_proto] eq ""} { return 0 }
          ::practice::load_design linked
          implement_proto
          set path [file join [dict get [::fc::lib_get] path] practice_core.block]
          expr {[get_flow_stage] eq "place_opt" && abs([::fc::floorplan_get util_target] - 0.60) < 1e-9 && [::fc::floorplan_get core_offset] eq {8 8} && [::fc::floorplan_get pins_placed] && [file exists $path]} }]]
}

::practice::init

proc practice_labs {args} {
  variable ::practice::labs
  puts [format "%-6s %-28s %s" "Lab" "Title" "State"]
  puts [string repeat "-" 60]
  foreach n [lsort -integer [dict keys $labs]] {
    set title [dict get $labs $n title]
    set state "ready"
    if {$n == $::practice::current} { set state "current" }
    puts [format "%-6s %-28s %s" $n $title $state]
  }
  puts ""
  puts "practice_start <n>   open a lab"
  puts "practice_check       grade the current lab"
  puts "practice_hint        hint for the first failing task"
  puts "practice_solution    print a solution"
  puts "practice_cheatsheet  collection and flow reminders"
  puts "practice_demo        run examples/proto_flow.tcl"
  return ""
}

proc practice_start {number} {
  variable ::practice::labs
  variable ::practice::current
  if {![dict exists $labs $number]} {
    ::fc::fail "no lab $number. Try practice_labs. (LAB-001)"
  }
  set current $number
  set lab [dict get $labs $number]
  puts "Lab $number — [dict get $lab title]"
  puts [string repeat "=" 60]
  puts [dict get $lab intro]
  puts ""
  set i 1
  foreach task [dict get $lab tasks] {
    puts [format "%d. %s" $i [dict get $task title]]
    incr i
  }
  puts ""
  if {$number == 2} {
    if {[::fc::has_lib]} {
      close_lib -force
      puts "Closed the previous library so create_lib can run."
    }
    puts "Kit root: $::fc::root"
  } elseif {$number >= 3} {
    puts "Loading a fresh linked practice_core into work/lab_session.ndm ..."
    ::practice::load_design linked
    puts "Current block: [current_block]   stage: [get_flow_stage]"
  }
  puts "When you are ready: practice_check"
  return ""
}

# Checks use return and global commands. eval keeps that inside this proc
# and in the global namespace, so info procs sees student procedures.
proc practice_eval_check {script} {
  eval $script
}

proc practice_check {args} {
  variable ::practice::labs
  variable ::practice::current
  if {$::practice::current == 0} {
    ::fc::fail "no lab is started. practice_start <n> (LAB-002)"
  }
  set lab [dict get $labs $::practice::current]
  set fail 0
  set first ""
  puts "Checking lab $::practice::current — [dict get $lab title]"
  foreach task [dict get $lab tasks] {
    set id [dict get $task id]
    set code [catch {practice_eval_check [dict get $task check]} result]
    if {$code} {
      puts [format "  FAIL  %-10s %s" $id $result]
      incr fail
      if {$first eq ""} { set first $task }
    } elseif {$result} {
      puts [format "  PASS  %-10s %s" $id [dict get $task title]]
    } else {
      puts [format "  FAIL  %-10s %s" $id [dict get $task title]]
      incr fail
      if {$first eq ""} { set first $task }
    }
  }
  if {$fail == 0} {
    puts "LAB PASS"
    return 1
  }
  puts "LAB FAIL: $fail task(s). Try practice_hint"
  return 0
}

proc practice_hint {args} {
  variable ::practice::labs
  variable ::practice::current
  if {$::practice::current == 0} {
    ::fc::fail "no lab is started (LAB-002)"
  }
  set lab [dict get $labs $::practice::current]
  set tasks [dict get $lab tasks]
  set wanted ""
  if {[llength $args] == 1} {
    set wanted [lindex $args 0]
  }
  foreach task $tasks {
    if {$wanted ne "" && [dict get $task id] ne $wanted} continue
    if {$wanted eq ""} {
      set code [catch {practice_eval_check [dict get $task check]} result]
      if {$code == 0 && $result} continue
    }
    puts "Task [dict get $task id]: [dict get $task title]"
    puts [dict get $task hint]
    return ""
  }
  if {$wanted ne ""} {
    ::fc::fail "no task '$wanted' in lab $::practice::current (LAB-003)"
  }
  puts "Every task currently passes."
  return ""
}

proc practice_solution {args} {
  variable ::practice::current
  if {$::practice::current == 0} {
    ::fc::fail "no lab is started (LAB-002)"
  }
  set path [file join $::fc::root labs solutions [format lab%02d.tcl $::practice::current]]
  if {![file exists $path]} {
    ::fc::fail "no solution file for lab $::practice::current (LAB-004)"
  }
  puts "Solution file: $path"
  puts "You can source it, or type the commands yourself."
  puts [string repeat "-" 60]
  set fh [open $path r]
  puts -nonewline [read $fh]
  close $fh
  return ""
}

proc practice_reset {args} {
  if {[::fc::has_lib]} {
    close_lib -force
  }
  set session [file join $::fc::root work lab_session.ndm]
  if {[file exists $session]} {
    file delete -force $session
  }
  foreach v {design_name target_util mods nleaves seq_names rf_cells clk_pins} {
    if {[info exists ::$v]} { unset ::$v }
  }
  foreach p {banner implement_proto} {
    if {[info procs $p] ne ""} { rename $p "" }
  }
  set ::practice::current 0
  puts "Session design closed. Lab progress cleared."
  return ""
}

proc practice_cheatsheet {args} {
  puts {
Collections
  set cells [get_cells -hierarchical -filter "is_sequential == true"]
  sizeof_collection $cells
  get_object_name $cells
  foreach_in_collection c $cells {
    echo "[get_object_name $c] [get_attribute $c ref_name]"
  }
  filter_collection $cells "area > 4 && ref_name =~ DFF*"
  remove_from_collection [all_inputs] [get_ports clk]

Patterns
  * and ? do not cross /
  get_cells *                 top-level cells only
  get_cells u_rf*/*           one level under u_rf0, u_rf1, ...
  get_cells -hierarchical *ff*    leaf name match at any level
  get_pins -of_objects [get_cells u_alu]

Filter operators
  == != > < >= <= =~ !~
  Combine with && and || and parentheses.
  true/false compare with boolean attributes such as is_sequential.

Flow
  initialize_floorplan -core_utilization 0.65 -side_ratio {1 1} -core_offset {10 10}
  place_pins -self
  create_placement -floorplan
  place_opt
  clock_opt
  route_auto
  route_opt
  report_qor
  redirect -file reports/qor.rpt { report_qor }

Stages: linked -> floorplanned -> placed -> place_opt -> clock_opt -> routed -> route_opt
Estimated WNS is negative until clock_opt, dips at route, and is positive after route_opt.
}
  return ""
}

proc practice_demo {args} {
  source [file join $::fc::root examples proto_flow.tcl]
  return ""
}

foreach {name summary syntax example} {
  practice_labs "List the practice labs" "practice_labs" "practice_labs"
  practice_start "Open a lab and, from lab 3 on, load the design" "practice_start n" "practice_start 1"
  practice_check "Grade the current lab" "practice_check" "practice_check"
  practice_hint "Show a hint for a failing task" "practice_hint ?task?" "practice_hint"
  practice_solution "Print the solution for the current lab" "practice_solution" "practice_solution"
  practice_reset "Close the session design and clear lab variables" "practice_reset" "practice_reset"
  practice_cheatsheet "Short reminder of collections and the flow" "practice_cheatsheet" "practice_cheatsheet"
  practice_demo "Build, floorplan, and route the demo block" "practice_demo" "practice_demo"
} {
  ::fc::register $name "Practice" $summary $syntax $example
}
