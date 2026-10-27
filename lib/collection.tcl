# Collection ids (_selN), filters, and the collection commands.
# get_* patterns use a glob in which * and ? do not cross '/'.
# Filter =~ uses ordinary Tcl glob, so * does cross '/'.

proc ::fc::is_collection {value} {
  variable collections
  if {![string match "_sel*" $value]} { return 0 }
  return [dict exists $collections $value]
}

proc ::fc::new_collection {class ids} {
  variable collections
  variable sel_counter
  incr sel_counter
  set id "_sel$sel_counter"
  dict set collections $id [list $class $ids]
  return $id
}

proc ::fc::collection_data {value} {
  variable collections
  if {![::fc::is_collection $value]} {
    ::fc::fail "expected a collection, got '$value'. Query commands return ids such as _sel1. Use get_object_name to build a Tcl list. (SEL-002)"
  }
  return [dict get $collections $value]
}

proc ::fc::collection_items {value} {
  return [lindex [::fc::collection_data $value] 1]
}

proc ::fc::collection_class {value} {
  return [lindex [::fc::collection_data $value] 0]
}

proc ::fc::collection_names {value} {
  set names [list]
  foreach id [::fc::collection_items $value] {
    lappend names [::fc::attr $id full_name]
  }
  return $names
}

proc ::fc::hier_match {pattern value} {
  set re "^"
  set n [string length $pattern]
  for {set i 0} {$i < $n} {incr i} {
    set c [string index $pattern $i]
    switch -- $c {
      "*" {
        if {[string index $pattern [expr {$i + 1}]] eq "*"} {
          append re ".*"
          incr i
        } else {
          append re {[^/]*}
        }
      }
      "?" { append re {[^/]} }
      "." - "^" - "\$" - "+" - "(" - ")" - "\[" - "\]" - "|" - "\\" - "\{" - "\}" {
        append re "\\" $c
      }
      default { append re $c }
    }
  }
  append re "\$"
  return [regexp -- $re $value]
}

proc ::fc::values_equal {a b} {
  if {$a eq $b} { return 1 }
  if {[string is boolean -strict $a] && [string is boolean -strict $b]} {
    return [expr {[string is true $a] == [string is true $b]}]
  }
  if {[string is double -strict $a] && [string is double -strict $b]} {
    return [expr {double($a) == double($b)}]
  }
  return 0
}

proc ::fc::f_cmp {actual op val} {
  switch -- $op {
    "==" { return [::fc::values_equal $actual $val] }
    "!=" { return [expr {![::fc::values_equal $actual $val]}] }
    "=~" { return [string match $val $actual] }
    "!~" { return [expr {![string match $val $actual]}] }
    default {
      if {![string is double -strict $actual] || ![string is double -strict $val]} {
        ::fc::fail "filter comparison '$actual $op $val' is not numeric (SEL-010)"
      }
      return [expr $actual $op $val]
    }
  }
}

proc ::fc::f_or {id eVar} {
  upvar 1 $eVar e
  set left [::fc::f_and $id e]
  while {1} {
    set e [string trimleft $e]
    if {[string match {||*} $e]} {
      set e [string range $e 2 end]
      set right [::fc::f_and $id e]
      set left [expr {$left || $right}]
    } else {
      break
    }
  }
  return $left
}

proc ::fc::f_and {id eVar} {
  upvar 1 $eVar e
  set left [::fc::f_term $id e]
  while {1} {
    set e [string trimleft $e]
    if {[string match {&&*} $e]} {
      set e [string range $e 2 end]
      set right [::fc::f_term $id e]
      set left [expr {$left && $right}]
    } else {
      break
    }
  }
  return $left
}

proc ::fc::f_term {id eVar} {
  upvar 1 $eVar e
  set e [string trimleft $e]
  if {$e eq ""} {
    ::fc::fail "incomplete filter expression (SEL-010)"
  }
  if {[string index $e 0] eq "("} {
    set e [string range $e 1 end]
    set v [::fc::f_or $id e]
    set e [string trimleft $e]
    if {[string index $e 0] ne ")"} {
      ::fc::fail "filter missing ')' (SEL-010)"
    }
    set e [string range $e 1 end]
    return $v
  }
  if {![regexp {^[A-Za-z_][A-Za-z0-9_]*} $e attr]} {
    ::fc::fail "filter expected an attribute near '$e' (SEL-010)"
  }
  set e [string range $e [string length $attr] end]
  set e [string trimleft $e]
  set op ""
  foreach candidate {=~ !~ == != >= <= > <} {
    if {[string match ${candidate}* $e]} {
      set op $candidate
      break
    }
  }
  if {$op eq ""} {
    ::fc::fail "filter expected an operator near '$e' (SEL-010)"
  }
  set e [string trimleft [string range $e [string length $op] end]]
  if {[string index $e 0] eq "\""} {
    set end [string first "\"" $e 1]
    if {$end < 0} {
      ::fc::fail "unterminated filter string (SEL-010)"
    }
    set val [string range $e 1 [expr {$end - 1}]]
    set e [string range $e [expr {$end + 1}] end]
  } else {
    if {![regexp {^[^\s)&|]+} $e val]} {
      ::fc::fail "filter expected a value near '$e' (SEL-010)"
    }
    set e [string range $e [string length $val] end]
  }
  set actual [::fc::attr $id $attr]
  return [::fc::f_cmp $actual $op $val]
}

proc ::fc::filter_ids {ids expr} {
  set out [list]
  foreach id $ids {
    set e $expr
    if {[::fc::f_or $id e]} {
      set rest [string trim $e]
      if {$rest ne ""} {
        ::fc::fail "bad filter near '$rest' (SEL-010)"
      }
      lappend out $id
    } else {
      set rest [string trim $e]
      if {$rest ne ""} {
        ::fc::fail "bad filter near '$rest' (SEL-010)"
      }
    }
  }
  return $out
}

proc sizeof_collection {collection} {
  return [llength [::fc::collection_items $collection]]
}

proc get_object_name {collection} {
  set names [::fc::collection_names $collection]
  if {[llength $names] == 1} {
    return [lindex $names 0]
  }
  return $names
}

proc foreach_in_collection {varName collection body} {
  lassign [::fc::collection_data $collection] class ids
  foreach id $ids {
    set one [::fc::new_collection $class [list $id]]
    uplevel 1 [list set $varName $one]
    set code [catch {uplevel 1 $body} result opts]
    switch -- $code {
      0 {}
      1 { return -options $opts $result }
      2 { return -code return -options $opts $result }
      3 { return "" }
      4 {}
      default { return -options $opts $result }
    }
  }
  return ""
}

proc filter_collection {collection expr} {
  lassign [::fc::collection_data $collection] class ids
  return [::fc::new_collection $class [::fc::filter_ids $ids $expr]]
}

proc index_collection {collection index} {
  lassign [::fc::collection_data $collection] class ids
  if {![string is integer -strict $index]} {
    ::fc::fail "index_collection index must be an integer (SEL-005)"
  }
  if {$index < 0 || $index >= [llength $ids]} {
    ::fc::fail "collection index $index is out of range (SEL-005)"
  }
  return [::fc::new_collection $class [list [lindex $ids $index]]]
}

proc add_to_collection {a b} {
  lassign [::fc::collection_data $a] ca ia
  lassign [::fc::collection_data $b] cb ib
  if {[llength $ia] > 0 && [llength $ib] > 0 && $ca ne $cb} {
    ::fc::fail "cannot add a $cb collection to a $ca collection (SEL-006)"
  }
  set class $ca
  if {[llength $ia] == 0} { set class $cb }
  set out $ia
  foreach id $ib {
    if {[lsearch -exact $out $id] < 0} {
      lappend out $id
    }
  }
  return [::fc::new_collection $class $out]
}

proc remove_from_collection {a b} {
  lassign [::fc::collection_data $a] ca ia
  lassign [::fc::collection_data $b] cb ib
  if {[llength $ia] > 0 && [llength $ib] > 0 && $ca ne $cb} {
    ::fc::fail "cannot remove a $cb collection from a $ca collection (SEL-006)"
  }
  set out [list]
  foreach id $ia {
    if {[lsearch -exact $ib $id] < 0} {
      lappend out $id
    }
  }
  return [::fc::new_collection $ca $out]
}

proc compare_collections {a b} {
  lassign [::fc::collection_data $a] ca ia
  lassign [::fc::collection_data $b] cb ib
  if {$ca ne $cb} { return 1 }
  set sa [lsort -unique $ia]
  set sb [lsort -unique $ib]
  return [expr {$sa eq $sb ? 0 : 1}]
}

proc copy_collection {collection} {
  lassign [::fc::collection_data $collection] class ids
  return [::fc::new_collection $class $ids]
}

proc sort_collection {args} {
  set descending 0
  set xs $args
  set rest [list]
  while {[llength $xs]} {
    set a [lindex $xs 0]
    if {$a eq "-descending"} {
      set descending 1
      set xs [lrange $xs 1 end]
    } else {
      lappend rest $a
      set xs [lrange $xs 1 end]
    }
  }
  if {[llength $rest] != 2} {
    ::fc::fail "usage: sort_collection ?-descending? collection attribute (SEL-007)"
  }
  set collection [lindex $rest 0]
  set attr [lindex $rest 1]
  lassign [::fc::collection_data $collection] class ids
  set rows [list]
  foreach id $ids {
    lappend rows [list [::fc::attr $id $attr] $id]
  }
  if {$descending} {
    set rows [lsort -decreasing -dictionary -index 0 $rows]
  } else {
    set rows [lsort -dictionary -index 0 $rows]
  }
  set out [list]
  foreach row $rows {
    lappend out [lindex $row 1]
  }
  return [::fc::new_collection $class $out]
}

foreach {name summary syntax example} {
  sizeof_collection "Count objects in a collection" "sizeof_collection collection" "sizeof_collection \[get_cells\]"
  get_object_name "Tcl list (or one name) of full names" "get_object_name collection" "set names \[get_object_name \[get_ports\]\]"
  foreach_in_collection "Loop; the variable is a one-object collection" "foreach_in_collection var collection body" "foreach_in_collection c \[all_registers\] { echo \[get_object_name \$c\] }"
  filter_collection "Keep objects whose attributes match" "filter_collection collection expr" "filter_collection \[get_cells -hierarchical\] \"is_sequential == true\""
  index_collection "One object by 0-based index" "index_collection collection index" "index_collection \[get_cells\] 0"
  add_to_collection "Union of two collections of the same class" "add_to_collection a b" "add_to_collection \[get_ports clk\] \[get_ports rst_n\]"
  remove_from_collection "Objects in a that are not in b" "remove_from_collection a b" "remove_from_collection \[all_inputs\] \[get_ports clk\]"
  compare_collections "Return 0 when both collections hold the same objects" "compare_collections a b" "compare_collections \[get_ports clk\] \[get_ports clk\]"
  copy_collection "Duplicate a collection id" "copy_collection collection" "set c2 \[copy_collection \$c\]"
  sort_collection "Sort by an attribute" "sort_collection ?-descending? collection attribute" "sort_collection \[get_cells -hierarchical\] area"
} {
  ::fc::register $name "Collections" $summary $syntax $example
}
