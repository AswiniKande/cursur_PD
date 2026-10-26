# Text reports. Timing is estimated from the flow stage so scripts can
# practice redirect, grep, and collection filters against stable numbers.

proc ::fc::rpt_rule {} {
  puts [string repeat "-" 72]
}

proc ::fc::rpt_header {title} {
  set b [::fc::block_get]
  puts [string repeat "*" 72]
  puts "Report : $title"
  puts "Design : [dict get $b name]"
  puts "Stage  : [dict get $b stage]"
  puts [string repeat "*" 72]
}

proc ::fc::rpt_row {label value} {
  puts [format "  %-28s %s" $label $value]
}

proc report_design {args} {
  ::fc::require_linked
  set b [::fc::block_get]
  set m [::fc::metrics]
  ::fc::rpt_header "design"
  ::fc::rpt_row "Library" [::fc::current_lib_name]
  ::fc::rpt_row "Top" [dict get $b top]
  ::fc::rpt_row "Scenario" [dict get $m scenario]
  ::fc::rpt_row "Leaf cells" [dict get $m leaf]
  ::fc::rpt_row "Sequential cells" [dict get $m sequential]
  ::fc::rpt_row "Hierarchical cells" [dict get $m hierarchical]
  ::fc::rpt_row "Cell area" [dict get $m area]
  ::fc::rpt_row "Ports" [llength [::fc::class_ids_in $b port]]
  ::fc::rpt_row "Nets" [llength [::fc::class_ids_in $b net]]
  set clocks [list]
  foreach id [::fc::class_ids_in $b clock] {
    lappend clocks "[dict get $b objects $id name]([dict get $b objects $id period])"
  }
  ::fc::rpt_row "Clocks" [join $clocks {, }]
  return ""
}

proc report_hierarchy {args} {
  ::fc::require_linked
  set b [::fc::block_get]
  ::fc::rpt_header "hierarchy"
  puts [dict get $b name]
  ::fc::dump_hier $b "" "  "
  return ""
}

proc ::fc::dump_hier {b parent indent} {
  set rows [list]
  foreach id [::fc::class_ids_in $b cell] {
    if {[dict get $b objects $id parent] eq $parent} {
      lappend rows [list [dict get $b objects $id full_name] $id]
    }
  }
  foreach row [lsort -dictionary -index 0 $rows] {
    set id [lindex $row 1]
    set o [dict get $b objects $id]
    puts "$indent[dict get $o full_name] ([dict get $o ref_name])"
    if {[dict get $o is_hierarchical] eq "true"} {
      ::fc::dump_hier $b [dict get $o full_name] "$indent  "
    }
  }
}

proc report_units {args} {
  ::fc::require_lib
  set tech [::fc::tech_dict]
  ::fc::rpt_header "units"
  puts "Technology : [dict get $tech name]"
  dict for {k v} [dict get $tech units] {
    ::fc::rpt_row $k $v
  }
  ::fc::rpt_row "site" "[dict get $tech site_name] [dict get $tech site_w] x [dict get $tech site_h]"
  foreach layer [dict get $tech layers] {
    puts [format "  layer %-8s %-12s pitch %s" [dict get $layer name] [dict get $layer direction] [dict get $layer pitch]]
  }
  return ""
}

proc report_qor {args} {
  foreach a $args {
    if {$a ne "-summary"} {
      ::fc::fail "unknown option '$a' for report_qor (RPT-001)"
    }
  }
  ::fc::require_linked
  set m [::fc::metrics]
  ::fc::rpt_header "qor"
  puts "Estimated practice QoR. Slack tracks the flow stage; it is not a timer."
  ::fc::rpt_rule
  ::fc::rpt_row "Scenario" [dict get $m scenario]
  ::fc::rpt_row "Clock period (ns)" [dict get $m period]
  ::fc::rpt_row "Leaf cell count" [dict get $m leaf]
  ::fc::rpt_row "Sequential cell count" [dict get $m sequential]
  ::fc::rpt_row "Hierarchical cell count" [dict get $m hierarchical]
  ::fc::rpt_row "Cell area" [dict get $m area]
  ::fc::rpt_row "Core utilization" [dict get $m util]
  ::fc::rpt_row "WNS (ns)" [dict get $m wns]
  ::fc::rpt_row "TNS (ns)" [dict get $m tns]
  ::fc::rpt_row "Hold WNS (ns)" [dict get $m hold]
  ::fc::rpt_row "Leakage (mw)" [dict get $m leakage]
  ::fc::rpt_row "Total power (mw)" [dict get $m total_power]
  return ""
}

proc report_utilization {args} {
  ::fc::require_floorplan
  set b [::fc::block_get]
  set fp [dict get $b floorplan]
  set m [::fc::metrics]
  ::fc::rpt_header "utilization"
  ::fc::rpt_row "Core width (um)" [format %.3f [dict get $fp width]]
  ::fc::rpt_row "Core height (um)" [format %.3f [dict get $fp height]]
  ::fc::rpt_row "Core area" [format %.3f [dict get $fp core_area]]
  ::fc::rpt_row "Die width (um)" [format %.3f [dict get $fp die_width]]
  ::fc::rpt_row "Die height (um)" [format %.3f [dict get $fp die_height]]
  ::fc::rpt_row "Cell area" [dict get $m area]
  ::fc::rpt_row "Target utilization" [format %.3f [dict get $fp util_target]]
  ::fc::rpt_row "Utilization" [dict get $m util]
  ::fc::rpt_row "Core offset" [join [dict get $fp core_offset] { }]
  ::fc::rpt_row "Side ratio" [join [dict get $fp side_ratio] { }]
  return ""
}

proc report_floorplan {args} {
  ::fc::require_floorplan
  set b [::fc::block_get]
  set fp [dict get $b floorplan]
  report_utilization
  puts ""
  puts "Ports"
  foreach id [lsort [::fc::class_ids_in $b port]] {
    set o [dict get $b objects $id]
    if {[dict get $o side] eq ""} {
      puts [format "  %-16s %-6s unplaced" [dict get $o full_name] [dict get $o direction]]
    } else {
      puts [format "  %-16s %-6s %-6s offset %s" [dict get $o full_name] [dict get $o direction] [dict get $o side] [dict get $o offset]]
    }
  }
  puts ""
  puts "Blockages"
  if {[llength [dict get $fp blockages]] == 0} { puts "  (none)" }
  foreach item [dict get $fp blockages] {
    set extra ""
    if {[dict exists $item layers]} { set extra " layers [join [dict get $item layers] ,]" }
    puts "  [dict get $item class] [dict get $item name] bbox [join [dict get $item bbox] { }]$extra"
  }
  puts "Bounds"
  if {[llength [dict get $fp bounds]] == 0} { puts "  (none)" }
  foreach item [dict get $fp bounds] {
    puts "  [dict get $item name] bbox [join [dict get $item bbox] { }]"
  }
  return ""
}

proc report_clocks {args} {
  ::fc::require_linked
  set b [::fc::block_get]
  ::fc::rpt_header "clocks"
  set ids [::fc::class_ids_in $b clock]
  if {[llength $ids] == 0} {
    puts "(no clocks)"
    return ""
  }
  puts [format "%-16s %10s  %-16s  %s" "Name" "Period" "Waveform" "Sources"]
  ::fc::rpt_rule
  foreach id $ids {
    set o [dict get $b objects $id]
    puts [format "%-16s %10s  %-16s  %s" [dict get $o name] [dict get $o period] [join [dict get $o waveform] { }] [join [dict get $o sources] { }]]
  }
  return ""
}

proc report_constraints {args} {
  ::fc::require_linked
  set b [::fc::block_get]
  ::fc::rpt_header "constraints"
  set cs [dict get $b constraints]
  if {[llength $cs] == 0} {
    puts "(no constraints recorded)"
    return ""
  }
  set i 1
  foreach c $cs {
    puts [format "%3d  %-16s %s" $i [dict get $c kind] [dict remove $c kind]]
    incr i
  }
  return ""
}

proc report_scenarios {args} {
  ::fc::require_linked
  set b [::fc::block_get]
  ::fc::rpt_header "scenarios"
  puts [format "%-20s %-8s %s" "Name" "Active" "Current"]
  ::fc::rpt_rule
  foreach id [::fc::class_ids_in $b scenario] {
    set o [dict get $b objects $id]
    set cur [expr {[dict get $o name] eq [dict get $b current_scenario] ? "yes" : ""}]
    puts [format "%-20s %-8s %s" [dict get $o name] [dict get $o active] $cur]
  }
  return ""
}

proc report_power {args} {
  ::fc::require_linked
  set m [::fc::metrics]
  ::fc::rpt_header "power"
  puts "Estimated from library leakage plus a stage-independent switching term."
  ::fc::rpt_row "Leakage (mw)" [dict get $m leakage]
  ::fc::rpt_row "Dynamic (mw)" [dict get $m dynamic]
  ::fc::rpt_row "Total (mw)" [dict get $m total_power]
  set b [::fc::block_get]
  set pg [list]
  foreach id [::fc::class_ids_in $b net] {
    set kind [dict get $b objects $id net_type]
    if {$kind ne "signal"} {
      lappend pg "[dict get $b objects $id name] ($kind)"
    }
  }
  if {[llength $pg] == 0} {
    ::fc::rpt_row "PG nets" "(none — create_net -power VDD)"
  } else {
    ::fc::rpt_row "PG nets" [join $pg {, }]
  }
  return ""
}

proc report_reference {args} {
  ::fc::require_linked
  set b [::fc::block_get]
  ::fc::rpt_header "reference"
  set counts [dict create]
  set areas [dict create]
  foreach id [::fc::leaf_ids $b] {
    set ref [dict get $b objects $id ref_name]
    if {![dict exists $counts $ref]} {
      dict set counts $ref 0
      dict set areas $ref [dict get $b objects $id area]
    }
    dict incr counts $ref
  }
  puts [format "%-16s %8s %10s" "Reference" "Count" "Area"]
  ::fc::rpt_rule
  foreach ref [lsort [dict keys $counts]] {
    puts [format "%-16s %8d %10.3f" $ref [dict get $counts $ref] [dict get $areas $ref]]
  }
  return ""
}

proc ::fc::require_one {collection what} {
  set ids [::fc::collection_items $collection]
  if {[llength $ids] != 1} {
    ::fc::fail "$what expects one object, got [llength $ids] (RPT-002)"
  }
  return [lindex $ids 0]
}

proc report_cell {args} {
  ::fc::require_linked
  set connections 0
  set col ""
  foreach a $args {
    if {$a eq "-connections"} {
      set connections 1
    } elseif {$col eq ""} {
      set col $a
    } else {
      ::fc::fail "usage: report_cell ?-connections? collection (RPT-003)"
    }
  }
  if {$col eq ""} {
    ::fc::fail "usage: report_cell ?-connections? collection (RPT-003)"
  }
  set b [::fc::block_get]
  foreach id [::fc::collection_items $col] {
    if {[dict get $b objects $id object_class] ne "cell"} {
      ::fc::fail "report_cell expects cells (RPT-003)"
    }
    set o [dict get $b objects $id]
    puts "Cell [dict get $o full_name]"
    ::fc::rpt_row "Reference" [dict get $o ref_name]
    ::fc::rpt_row "Hierarchical" [dict get $o is_hierarchical]
    ::fc::rpt_row "Sequential" [dict get $o is_sequential]
    ::fc::rpt_row "Area" [dict get $o area]
    ::fc::rpt_row "Dont touch" [dict get $o dont_touch]
    ::fc::rpt_row "Placed" [dict get $o is_placed]
    if {[dict get $o is_placed] eq "true"} {
      ::fc::rpt_row "Origin" "[dict get $o x] [dict get $o y] [dict get $o orientation]"
    }
    if {$connections} {
      foreach pid [::fc::class_ids_in $b pin] {
        if {[dict get $b objects $pid cell] ne $id} continue
        set net [dict get $b objects $pid net]
        set nname ""
        if {$net ne "" && [dict exists $b objects $net]} {
          set nname [dict get $b objects $net full_name]
        }
        puts [format "    pin %-8s %-4s %s" [dict get $b objects $pid pin_name] [dict get $b objects $pid direction] $nname]
      }
    }
  }
  return ""
}

proc report_net {collection} {
  ::fc::require_linked
  set b [::fc::block_get]
  foreach id [::fc::collection_items $collection] {
    if {[dict get $b objects $id object_class] ne "net"} {
      ::fc::fail "report_net expects nets (RPT-004)"
    }
    set o [dict get $b objects $id]
    puts "Net [dict get $o full_name]"
    ::fc::rpt_row "Type" [dict get $o net_type]
    ::fc::rpt_row "Fanout" [dict get $o fanout]
    ::fc::rpt_row "Drivers" [dict get $o drivers]
    foreach cid [dict get $o connections] {
      puts "    [dict get $b objects $cid object_class] [dict get $b objects $cid full_name]"
    }
  }
  return ""
}

proc report_port {collection} {
  ::fc::require_linked
  set b [::fc::block_get]
  puts [format "%-16s %-8s %-8s %s" "Port" "Dir" "Clock" "Net"]
  ::fc::rpt_rule
  foreach id [::fc::collection_items $collection] {
    if {[dict get $b objects $id object_class] ne "port"} {
      ::fc::fail "report_port expects ports (RPT-005)"
    }
    set o [dict get $b objects $id]
    set net [dict get $o net]
    set nname $net
    if {[dict exists $b objects $net]} { set nname [dict get $b objects $net full_name] }
    puts [format "%-16s %-8s %-8s %s" [dict get $o full_name] [dict get $o direction] [dict get $o is_clock] $nname]
  }
  return ""
}

proc report_attribute {args} {
  ::fc::require_linked
  if {[llength $args] < 1} {
    ::fc::fail "usage: report_attribute collection ?attr ...? (RPT-006)"
  }
  set col [lindex $args 0]
  set keys [lrange $args 1 end]
  set ids [::fc::collection_items $col]
  if {[llength $ids] == 0} {
    puts "(empty collection)"
    return ""
  }
  if {[llength $keys] == 0} {
    set keys [list_attributes $col]
  }
  foreach id $ids {
    puts "Attributes of [::fc::attr $id full_name]"
    foreach k $keys {
      puts [format "  %-24s %s" $k [::fc::attr $id $k]]
    }
  }
  return ""
}

proc report_timing {args} {
  ::fc::require_linked
  set max_paths 1
  set delay max
  set from ""
  set to ""
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -max_paths { set max_paths [::fc::take xs] }
      -nworst { ::fc::take xs }
      -delay_type { set delay [::fc::take xs] }
      -from { set from [::fc::take xs] }
      -to { set to [::fc::take xs] }
      -nosplit {}
      default { ::fc::fail "unknown option '$a' for report_timing (RPT-007)" }
    }
  }
  if {![string is integer -strict $max_paths] || $max_paths < 1} {
    ::fc::fail "-max_paths must be a positive integer (RPT-007)"
  }
  if {$max_paths > 20} { set max_paths 20 }
  set m [::fc::metrics]
  set b [::fc::block_get]
  ::fc::rpt_header "timing"
  puts "Estimated practice timing for stage [dict get $m stage]. Not a signoff report."
  if {$delay eq "min"} {
    ::fc::rpt_row "Hold WNS (ns)" [dict get $m hold]
    return ""
  }
  if {$delay ne "max"} {
    ::fc::fail "-delay_type must be max or min (RPT-007)"
  }
  if {[dict get $m wns] eq "n/a"} {
    puts "Timing is not available at this stage."
    return ""
  }
  set regs [list]
  foreach id [::fc::leaf_ids $b] {
    if {[dict get $b objects $id is_sequential] eq "true"} {
      lappend regs [list [dict get $b objects $id full_name] $id]
    }
  }
  set regs [lsort -dictionary -index 0 $regs]
  if {$from ne ""} {
    set allow [::fc::collection_items $from]
    set kept [list]
    foreach row $regs {
      if {[lsearch -exact $allow [lindex $row 1]] >= 0} { lappend kept $row }
    }
    set regs $kept
  }
  if {$to ne ""} {
    set allow [::fc::collection_items $to]
    set kept [list]
    foreach row $regs {
      if {[lsearch -exact $allow [lindex $row 1]] >= 0} { lappend kept $row }
    }
    set regs $kept
  }
  set n [llength $regs]
  if {$n == 0} {
    puts "No sequential endpoints match."
    return ""
  }
  set period [dict get $m period]
  set setup 0.040
  set latency 0.050
  set required [expr {$period + $latency - $setup}]
  set shown 0
  for {set i 0} {$i < $n && $shown < $max_paths} {incr i} {
    set srow [lindex $regs $i]
    set erow [lindex $regs [expr {($i + 1) % $n}]]
    set slack [expr {[dict get $m wns] + 0.004 * $i}]
    set arrival [expr {$required - $slack}]
    set sname [lindex $srow 0]
    set ename [lindex $erow 0]
    set status [expr {$slack < 0 ? "VIOLATED" : "MET"}]
    puts ""
    puts "Startpoint: $sname (rising edge-triggered flip-flop clocked by clk)"
    puts "Endpoint: $ename (rising edge-triggered flip-flop clocked by clk)"
    puts "Path Group: clk"
    puts "Scenario: [dict get $m scenario]"
    puts [format "%-42s %10s %10s" "Point" "Incr" "Path"]
    ::fc::rpt_rule
    set qdelay 0.080
    set mid [expr {$arrival - $qdelay}]
    if {$mid < 0} { set mid 0.0 }
    puts [format "%-42s %10.3f %10.3f" "clock clk (rise edge)" 0.0 0.0]
    puts [format "%-42s %10.3f %10.3f" "$sname/CK" 0.0 0.0]
    puts [format "%-42s %10.3f %10.3f" "$sname/Q" $qdelay $qdelay]
    puts [format "%-42s %10.3f %10.3f" "$ename/D" $mid $arrival]
    puts [format "%-42s %10s %10.3f" "data arrival time" "" $arrival]
    puts [format "%-42s %10.3f %10.3f" "clock clk (rise edge)" $period $period]
    puts [format "%-42s %10.3f %10.3f" "clock network delay" $latency [expr {$period + $latency}]]
    puts [format "%-42s %10.3f %10.3f" "library setup time" [expr {-$setup}] $required]
    puts [format "%-42s %10s %10.3f" "data required time" "" $required]
    ::fc::rpt_rule
    puts [format "%-42s %10s %10.3f" "slack ($status)" "" $slack]
    incr shown
  }
  return ""
}

foreach {name summary syntax example} {
  report_design "Summarize the current block" "report_design" "report_design"
  report_hierarchy "Print the cell tree" "report_hierarchy" "report_hierarchy"
  report_units "Show technology units and layers" "report_units" "report_units"
  report_qor "Estimated QoR for the current stage" "report_qor ?-summary?" "report_qor"
  report_utilization "Core size and utilization" "report_utilization" "report_utilization"
  report_floorplan "Utilization, ports, blockages, and bounds" "report_floorplan" "report_floorplan"
  report_clocks "Clocks in the current block" "report_clocks" "report_clocks"
  report_constraints "Constraints recorded from SDC" "report_constraints" "report_constraints"
  report_scenarios "Scenarios and which one is current" "report_scenarios" "report_scenarios"
  report_power "Estimated leakage and switching" "report_power" "report_power"
  report_reference "Leaf reference counts" "report_reference" "report_reference"
  report_cell "Attributes of cells, optionally with pins" \
    "report_cell ?-connections? collection" "report_cell -connections \[get_cells u_ctrl\]"
  report_net "Net type, fanout, and connections" "report_net collection" "report_net \[get_nets clk\]"
  report_port "Port direction table" "report_port collection" "report_port \[get_ports\]"
  report_attribute "Print selected attributes" \
    "report_attribute collection ?attr ...?" "report_attribute \[get_cells u_alu\] ref_name area"
  report_timing "Estimated setup or hold report" \
    "report_timing ?-max_paths N? ?-delay_type max|min? ?-from col? ?-to col?" \
    "report_timing -max_paths 3"
} {
  ::fc::register $name "Reports" $summary $syntax $example
}
