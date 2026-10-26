# Floorplan and the estimated implementation flow.
# Timing numbers are deterministic practice values, not signoff delays.

proc ::fc::stage_names {} {
  return {none linked floorplanned placed place_opt clock_opt routed route_opt}
}

proc ::fc::stage_index {name} {
  set i [lsearch -exact [::fc::stage_names] $name]
  if {$i < 0} {
    ::fc::fail "unknown flow stage '$name' (FLOW-000)"
  }
  return $i
}

proc ::fc::require_min_stage {need} {
  set cur [dict get [::fc::block_get] stage]
  if {[::fc::stage_index $cur] < [::fc::stage_index $need]} {
    ::fc::fail "flow stage is '$cur'; this command needs '$need' or later (FLOW-001)"
  }
}

proc ::fc::set_stage {new} {
  set b [::fc::block_get]
  dict set b stage $new
  dict set b dirty 1
  ::fc::block_set $b
}

proc ::fc::advance_stage {new} {
  set cur [dict get [::fc::block_get] stage]
  if {[::fc::stage_index $cur] < [::fc::stage_index $new]} {
    ::fc::set_stage $new
  }
}

proc ::fc::has_floorplan {} {
  set b [::fc::block_get]
  return [expr {[dict exists $b floorplan width]}]
}

proc ::fc::require_floorplan {} {
  ::fc::require_linked
  if {![::fc::has_floorplan]} {
    ::fc::fail "floorplan is not initialized (FLOW-002)"
  }
}

proc ::fc::floorplan_get {key} {
  set b [::fc::block_get]
  if {![dict exists $b floorplan $key]} { return "" }
  return [dict get $b floorplan $key]
}

proc ::fc::tech_dict {} {
  return [dict get [::fc::lib_get] tech]
}

proc ::fc::snap_up {value step} {
  if {$step <= 0} { return $value }
  return [expr {ceil(double($value) / double($step)) * double($step)}]
}

proc ::fc::leaf_ids {b} {
  set out [list]
  foreach id [::fc::class_ids_in $b cell] {
    if {[dict get $b objects $id is_hierarchical] eq "false"} {
      lappend out $id
    }
  }
  return $out
}

proc ::fc::cell_area_of {b} {
  set area 0.0
  foreach id [::fc::leaf_ids $b] {
    set area [expr {$area + [dict get $b objects $id area]}]
  }
  return $area
}

proc ::fc::clear_placement {bVar} {
  upvar 1 $bVar b
  foreach id [::fc::class_ids_in $b cell] {
    dict set b objects $id x ""
    dict set b objects $id y ""
    dict set b objects $id is_placed false
  }
}

proc ::fc::place_leaves {bVar} {
  upvar 1 $bVar b
  set tech [::fc::tech_dict]
  set site_w [dict get $tech site_w]
  set site_h [dict get $tech site_h]
  set width [dict get $b floorplan width]
  set x 0.0
  set y 0.0
  foreach id [lsort [::fc::leaf_ids $b]] {
    set area [dict get $b objects $id area]
    set sites [expr {max(1, int(ceil($area)))}]
    set w [expr {$sites * $site_w}]
    if {$x > 0 && ($x + $w) > ($width + 1e-9)} {
      set x 0.0
      set y [expr {$y + $site_h}]
    }
    dict set b objects $id x [format %.3f $x]
    dict set b objects $id y [format %.3f $y]
    dict set b objects $id is_placed true
    dict set b objects $id orientation N
    set x [expr {$x + $w}]
  }
}

proc ::fc::parse_pair {value what} {
  if {[llength $value] == 1} {
    set value [list [lindex $value 0] [lindex $value 0]]
  }
  if {[llength $value] != 2} {
    ::fc::fail "$what expects one number or a pair (FLOW-003)"
  }
  foreach n $value {
    if {![string is double -strict $n]} {
      ::fc::fail "$what expects numbers (FLOW-003)"
    }
  }
  return $value
}

proc ::fc::parse_bbox {value} {
  if {[llength $value] != 4} {
    ::fc::fail "bbox expects four numbers: xl yl xh yh (FLOW-004)"
  }
  foreach n $value {
    if {![string is double -strict $n]} {
      ::fc::fail "bbox expects numbers (FLOW-004)"
    }
  }
  return $value
}

proc initialize_floorplan {args} {
  ::fc::require_linked
  set util ""
  set shape ""
  set ratio {1 1}
  set offset {0 0}
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -core_utilization { set util [::fc::take xs] }
      -side_ratio { set ratio [::fc::parse_pair [::fc::take xs] -side_ratio] }
      -core_offset { set offset [::fc::parse_pair [::fc::take xs] -core_offset] }
      -shape -
      -core_size { set shape [::fc::parse_pair [::fc::take xs] -shape] }
      default { ::fc::fail "unknown option '$a' for initialize_floorplan (FLOW-005)" }
    }
  }
  if {$util ne "" && $shape ne ""} {
    ::fc::fail "give -core_utilization or -shape, not both (FLOW-005)"
  }
  if {$util eq "" && $shape eq ""} {
    ::fc::fail "usage: initialize_floorplan -core_utilization frac ?-side_ratio {w h}? ?-core_offset {x y}? (FLOW-005)"
  }
  set b [::fc::block_get]
  set cell_area [::fc::cell_area_of $b]
  if {$cell_area <= 0} {
    ::fc::fail "block has no cell area to floorplan (FLOW-006)"
  }
  set tech [::fc::tech_dict]
  set site [dict get $tech site_w]
  if {$util ne ""} {
    if {![string is double -strict $util] || $util <= 0 || $util > 1} {
      ::fc::fail "-core_utilization must be between 0 and 1 (FLOW-005)"
    }
    set core_area [expr {$cell_area / double($util)}]
    set rw [lindex $ratio 0]
    set rh [lindex $ratio 1]
    if {$rw <= 0 || $rh <= 0} {
      ::fc::fail "-side_ratio values must be positive (FLOW-005)"
    }
    set width [expr {sqrt($core_area * double($rw) / double($rh))}]
    set height [expr {$core_area / $width}]
  } else {
    set width [lindex $shape 0]
    set height [lindex $shape 1]
    if {$width <= 0 || $height <= 0} {
      ::fc::fail "-shape values must be positive (FLOW-005)"
    }
    set util [expr {$cell_area / ($width * $height)}]
  }
  set width [::fc::snap_up $width $site]
  set height [::fc::snap_up $height $site]
  set ox [lindex $offset 0]
  set oy [lindex $offset 1]
  if {[::fc::stage_index [dict get $b stage]] > [::fc::stage_index floorplanned]} {
    ::fc::warn_msg FLOW-010 "floorplan changed; placement and optimization results were cleared"
  }
  ::fc::clear_placement b
  dict set b floorplan [dict create \
    util_target $util \
    side_ratio $ratio \
    core_offset [list $ox $oy] \
    width $width \
    height $height \
    core_area [expr {$width * $height}] \
    die_width [expr {$width + 2.0 * $ox}] \
    die_height [expr {$height + 2.0 * $oy}] \
    cell_area $cell_area \
    pins_placed 0 \
    blockages [list] \
    bounds [list]]
  dict set b stage floorplanned
  dict set b dirty 1
  ::fc::block_set $b
  ::fc::info_msg FP-100 [format "core %.3f x %.3f um, target utilization %.3f" $width $height $util]
  return ""
}

proc place_pins {args} {
  ::fc::require_floorplan
  set self 0
  foreach a $args {
    switch -- $a {
      -self { set self 1 }
      default { ::fc::fail "unknown option '$a' for place_pins (FLOW-007)" }
    }
  }
  if {!$self} {
    ::fc::fail "usage: place_pins -self (FLOW-007)"
  }
  set b [::fc::block_get]
  set height [dict get $b floorplan height]
  set inputs [list]
  set outputs [list]
  foreach id [::fc::class_ids_in $b port] {
    set dir [dict get $b objects $id direction]
    if {$dir eq "out"} {
      lappend outputs $id
    } else {
      lappend inputs $id
    }
  }
  set i 0
  set n [llength $inputs]
  set step [expr {$n > 0 ? $height / ($n + 1.0) : 0}]
  foreach id $inputs {
    incr i
    dict set b objects $id side left
    dict set b objects $id offset [format %.3f [expr {$step * $i}]]
  }
  set i 0
  set n [llength $outputs]
  set step [expr {$n > 0 ? $height / ($n + 1.0) : 0}]
  foreach id $outputs {
    incr i
    dict set b objects $id side right
    dict set b objects $id offset [format %.3f [expr {$step * $i}]]
  }
  dict set b floorplan pins_placed 1
  dict set b dirty 1
  ::fc::block_set $b
  ::fc::info_msg FP-101 "placed [expr {[llength $inputs] + [llength $outputs]}] ports"
  return ""
}

proc create_placement {args} {
  ::fc::require_floorplan
  foreach a $args {
    switch -- $a {
      -floorplan {}
      default { ::fc::fail "unknown option '$a' for create_placement (FLOW-008)" }
    }
  }
  set b [::fc::block_get]
  ::fc::place_leaves b
  if {[::fc::stage_index [dict get $b stage]] < [::fc::stage_index placed]} {
    dict set b stage placed
  }
  dict set b dirty 1
  ::fc::block_set $b
  ::fc::info_msg FP-102 "placed [::fc::count_cells $b leaf] leaf cells"
  return ""
}

proc ::fc::add_blockage {class name bbox extra} {
  ::fc::require_floorplan
  if {$name eq ""} {
    set name "${class}_[expr {[llength [::fc::floorplan_get blockages]] + [llength [::fc::floorplan_get bounds]] + 1}]"
  }
  set b [::fc::block_get]
  set item [dict merge [dict create class $class name $name bbox $bbox] $extra]
  if {$class eq "bound"} {
    set items [dict get $b floorplan bounds]
    lappend items $item
    dict set b floorplan bounds $items
  } else {
    set items [dict get $b floorplan blockages]
    lappend items $item
    dict set b floorplan blockages $items
  }
  dict set b dirty 1
  ::fc::block_set $b
  ::fc::info_msg FP-103 "created $class $name"
  return $name
}

proc create_placement_blockage {args} {
  set name ""
  set bbox ""
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -name { set name [::fc::take xs] }
      -bbox { set bbox [::fc::parse_bbox [::fc::take xs]] }
      default { ::fc::fail "unknown option '$a' for create_placement_blockage (FLOW-009)" }
    }
  }
  if {$bbox eq ""} {
    ::fc::fail "usage: create_placement_blockage -name name -bbox {xl yl xh yh} (FLOW-009)"
  }
  return [::fc::add_blockage placement $name $bbox [dict create]]
}

proc create_routing_blockage {args} {
  set name ""
  set bbox ""
  set layers [list]
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -name { set name [::fc::take xs] }
      -bbox { set bbox [::fc::parse_bbox [::fc::take xs]] }
      -layers { set layers [::fc::as_list [::fc::take xs]] }
      default { ::fc::fail "unknown option '$a' for create_routing_blockage (FLOW-009)" }
    }
  }
  if {$bbox eq "" || [llength $layers] == 0} {
    ::fc::fail "usage: create_routing_blockage -name name -layers {M1 M2} -bbox {xl yl xh yh} (FLOW-009)"
  }
  return [::fc::add_blockage routing $name $bbox [dict create layers $layers]]
}

proc create_bound {args} {
  set name ""
  set bbox ""
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -name { set name [::fc::take xs] }
      -bbox { set bbox [::fc::parse_bbox [::fc::take xs]] }
      default { ::fc::fail "unknown option '$a' for create_bound (FLOW-009)" }
    }
  }
  if {$bbox eq ""} {
    ::fc::fail "usage: create_bound -name name -bbox {xl yl xh yh} (FLOW-009)"
  }
  return [::fc::add_blockage bound $name $bbox [dict create]]
}

proc check_floorplan {args} {
  ::fc::require_floorplan
  set b [::fc::block_get]
  set fp [dict get $b floorplan]
  set errors 0
  puts "Floorplan check for [dict get $b name]"
  set util [expr {[dict get $fp cell_area] / [dict get $fp core_area]}]
  puts [format "  core           %.3f x %.3f" [dict get $fp width] [dict get $fp height]]
  puts [format "  utilization    %.3f (target %.3f)" $util [dict get $fp util_target]]
  if {$util <= 0 || $util > 1.0} {
    puts "  ERROR utilization is outside (0, 1]"
    incr errors
  } elseif {$util > 0.85} {
    ::fc::warn_msg FP-110 "core utilization is above 0.85"
  }
  if {![dict get $fp pins_placed]} {
    ::fc::warn_msg FP-111 "ports are not placed; run place_pins -self"
  } else {
    puts "  ports          placed"
  }
  set nblk [llength [dict get $fp blockages]]
  set nbound [llength [dict get $fp bounds]]
  puts "  blockages      $nblk"
  puts "  bounds         $nbound"
  set die_w [dict get $fp die_width]
  set die_h [dict get $fp die_height]
  set ox [lindex [dict get $fp core_offset] 0]
  set oy [lindex [dict get $fp core_offset] 1]
  foreach item [dict get $fp blockages] {
    set box [dict get $item bbox]
    set xh [lindex $box 2]
    set yh [lindex $box 3]
    if {$xh > [expr {$die_w - $ox}] || $yh > [expr {$die_h - $oy}]} {
      ::fc::warn_msg FP-112 "blockage [dict get $item name] extends outside the core"
    }
  }
  if {$errors == 0} {
    puts "Floorplan check PASSED"
    return 1
  }
  puts "Floorplan check FAILED ($errors)"
  return 0
}

proc ::fc::slack_for_stage {stage} {
  # Worst setup slack in ns. Early stages miss; route_opt meets.
  set table [dict create \
    linked -0.450 \
    floorplanned -0.300 \
    placed -0.180 \
    place_opt -0.060 \
    clock_opt 0.010 \
    routed -0.030 \
    route_opt 0.040]
  if {![dict exists $table $stage]} { return "" }
  return [dict get $table $stage]
}

proc ::fc::primary_period {b} {
  set clocks [::fc::class_ids_in $b clock]
  if {[llength $clocks] == 0} { return 2.0 }
  return [dict get $b objects [lindex $clocks 0] period]
}

proc ::fc::metrics {} {
  set b [::fc::block_get]
  set leaves [::fc::leaf_ids $b]
  set nleaf [llength $leaves]
  set nseq 0
  set area 0.0
  set leak 0.0
  foreach id $leaves {
    set area [expr {$area + [dict get $b objects $id area]}]
    set leak [expr {$leak + [dict get $b objects $id leakage]}]
    if {[dict get $b objects $id is_sequential] eq "true"} { incr nseq }
  }
  set nhier [::fc::count_cells $b hier]
  set stage [dict get $b stage]
  set period [::fc::primary_period $b]
  set wns [::fc::slack_for_stage $stage]
  set tns "n/a"
  set hold "n/a"
  if {$wns ne ""} {
    if {$wns < 0} {
      set tns [format %.3f [expr {$wns * $nseq * 0.55}]]
    } else {
      set tns 0.000
    }
    set wns [format %.3f $wns]
  } else {
    set wns "n/a"
  }
  if {[::fc::stage_index $stage] >= [::fc::stage_index clock_opt]} {
    if {$stage eq "routed"} {
      set hold -0.010
    } else {
      set hold 0.015
    }
    set hold [format %.3f $hold]
  }
  set util "n/a"
  set core_area "n/a"
  if {[dict exists $b floorplan core_area]} {
    set core_area [dict get $b floorplan core_area]
    set util [format %.3f [expr {$area / $core_area}]]
  }
  set dyn [expr {$nleaf * 0.015 / $period}]
  return [dict create \
    stage $stage \
    leaf $nleaf \
    sequential $nseq \
    hierarchical $nhier \
    area [format %.3f $area] \
    leakage [format %.3f $leak] \
    dynamic [format %.3f $dyn] \
    total_power [format %.3f [expr {$leak + $dyn}]] \
    period $period \
    wns $wns \
    tns $tns \
    hold $hold \
    util $util \
    core_area $core_area \
    scenario [dict get $b current_scenario]]
}

proc ::fc::run_opt {name need next message} {
  ::fc::require_min_stage $need
  set before [dict get [::fc::block_get] stage]
  ::fc::advance_stage $next
  set m [::fc::metrics]
  ::fc::info_msg FLOW-100 "$message on [current_block] (was $before, now [dict get $m stage], WNS [dict get $m wns])"
  return ""
}

proc place_opt {args} {
  if {[llength $args]} {
    ::fc::fail "place_opt takes no options on this platform (FLOW-011)"
  }
  ::fc::require_min_stage placed
  return [::fc::run_opt place_opt placed place_opt "place_opt finished"]
}

proc clock_opt {args} {
  if {[llength $args]} {
    ::fc::fail "clock_opt takes no options on this platform (FLOW-011)"
  }
  return [::fc::run_opt clock_opt place_opt clock_opt "clock_opt finished"]
}

proc route_auto {args} {
  if {[llength $args]} {
    ::fc::fail "route_auto takes no options on this platform (FLOW-011)"
  }
  return [::fc::run_opt route_auto clock_opt routed "route_auto finished"]
}

proc route_opt {args} {
  if {[llength $args]} {
    ::fc::fail "route_opt takes no options on this platform (FLOW-011)"
  }
  return [::fc::run_opt route_opt routed route_opt "route_opt finished"]
}

proc compile_fusion {args} {
  if {[llength $args]} {
    ::fc::fail "compile_fusion takes no options here; floorplan first, then compile_fusion (FLOW-012)"
  }
  ::fc::require_floorplan
  set b [::fc::block_get]
  if {[::fc::stage_index [dict get $b stage]] < [::fc::stage_index placed]} {
    create_placement -floorplan
  }
  if {[::fc::stage_index [get_flow_stage]] < [::fc::stage_index place_opt]} { place_opt }
  if {[::fc::stage_index [get_flow_stage]] < [::fc::stage_index clock_opt]} { clock_opt }
  if {[::fc::stage_index [get_flow_stage]] < [::fc::stage_index routed]} { route_auto }
  if {[::fc::stage_index [get_flow_stage]] < [::fc::stage_index route_opt]} { route_opt }
  ::fc::info_msg FLOW-101 "compile_fusion reached [get_flow_stage]"
  return ""
}

foreach {name summary syntax example} {
  initialize_floorplan "Size the core from utilization or an explicit shape" \
    "initialize_floorplan -core_utilization frac ?-side_ratio {w h}? ?-core_offset {x y}?" \
    "initialize_floorplan -core_utilization 0.65 -side_ratio {1 1} -core_offset {10 10}"
  place_pins "Spread ports on the core boundary" "place_pins -self" "place_pins -self"
  create_placement "Legalize a quick placement" "create_placement ?-floorplan?" "create_placement -floorplan"
  create_placement_blockage "Keep cells out of a rectangle" \
    "create_placement_blockage -name name -bbox {xl yl xh yh}" \
    "create_placement_blockage -name keepout -bbox {0 0 5 5}"
  create_routing_blockage "Block routing on layers" \
    "create_routing_blockage -name name -layers {layers} -bbox {xl yl xh yh}" \
    "create_routing_blockage -name r1 -layers {M2} -bbox {0 0 5 5}"
  create_bound "Record a placement bound" \
    "create_bound -name name -bbox {xl yl xh yh}" \
    "create_bound -name alu_box -bbox {2 2 10 10}"
  check_floorplan "Print floorplan checks; returns 1 when they pass" "check_floorplan" "check_floorplan"
  place_opt "Advance to place_opt and refresh estimated QoR" "place_opt" "place_opt"
  clock_opt "Advance to clock_opt" "clock_opt" "clock_opt"
  route_auto "Advance to routed" "route_auto" "route_auto"
  route_opt "Advance to route_opt" "route_opt" "route_opt"
  compile_fusion "Run the remaining flow through route_opt" "compile_fusion" "compile_fusion"
} {
  ::fc::register $name "Flow" $summary $syntax $example
}
