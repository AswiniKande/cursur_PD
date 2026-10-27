# Design database: libraries, Verilog/SDC readers, link, and get_* queries.

proc ::fc::has_lib {} {
  variable db
  return [expr {[dict get $db current_lib] ne ""}]
}

proc ::fc::has_block {} {
  variable db
  return [expr {[dict get $db current_block] ne ""}]
}

proc ::fc::require_lib {} {
  if {![::fc::has_lib]} {
    ::fc::fail "no library is open (DES-001)"
  }
}

proc ::fc::require_block {} {
  ::fc::require_lib
  if {![::fc::has_block]} {
    ::fc::fail "no block is open (DES-001)"
  }
}

proc ::fc::require_linked {} {
  ::fc::require_block
  set b [::fc::block_get]
  if {![dict get $b linked]} {
    ::fc::fail "block '[dict get $b name]' is not linked; run link_block (DES-002)"
  }
}

proc ::fc::current_lib_name {} {
  variable db
  return [dict get $db current_lib]
}

proc ::fc::current_block_name {} {
  variable db
  ::fc::require_block
  return [dict get $db current_block]
}

proc ::fc::lib_get {} {
  variable db
  ::fc::require_lib
  return [dict get $db libs [dict get $db current_lib]]
}

proc ::fc::lib_set {lib} {
  variable db
  dict set db libs [dict get $db current_lib] $lib
}

proc ::fc::block_get {} {
  variable db
  ::fc::require_block
  return [dict get $db blocks [dict get $db current_block]]
}

proc ::fc::block_set {b} {
  variable db
  dict set db blocks [dict get $db current_block] $b
}

proc ::fc::new_block {name} {
  return [dict create \
    name $name \
    top $name \
    linked 0 \
    stage none \
    dirty 1 \
    objects [dict create] \
    class_ids [dict create] \
    floorplan [dict create] \
    constraints [list] \
    current_scenario ""]
}

proc ::fc::class_ids_in {b class} {
  if {![dict exists $b class_ids $class]} { return [list] }
  return [dict get $b class_ids $class]
}

proc ::fc::attr {id key} {
  set obj [::fc::object_get $id]
  if {![dict exists $obj $key]} { return "" }
  return [dict get $obj $key]
}

proc ::fc::object_get {id} {
  variable db
  if {[dict exists $db lib_objects $id]} {
    return [dict get $db lib_objects $id]
  }
  set b [::fc::block_get]
  if {![dict exists $b objects $id]} {
    ::fc::fail "object '$id' does not exist (SEL-004)"
  }
  return [dict get $b objects $id]
}

proc ::fc::set_attr {id key value} {
  variable db
  if {[dict exists $db lib_objects $id]} {
    dict set db lib_objects $id $key $value
    return
  }
  set b [::fc::block_get]
  if {![dict exists $b objects $id]} {
    ::fc::fail "object '$id' does not exist (SEL-004)"
  }
  dict set b objects $id $key $value
  dict set b dirty 1
  ::fc::block_set $b
}

proc ::fc::unset_attr {id key} {
  set b [::fc::block_get]
  if {[dict exists $b objects $id $key]} {
    dict unset b objects $id $key
    dict set b dirty 1
    ::fc::block_set $b
  }
}

proc ::fc::add_object {bVar class full extra} {
  upvar 1 $bVar b
  set id "${class}:${full}"
  if {[dict exists $b objects $id]} {
    ::fc::fail "duplicate $class '$full' (DES-003)"
  }
  set name [lindex [split $full /] end]
  set attrs [dict create \
    object_class $class \
    full_name $full \
    name $name \
    dont_touch false]
  set attrs [dict merge $attrs $extra]
  dict set b objects $id $attrs
  set ids [list]
  if {[dict exists $b class_ids $class]} {
    set ids [dict get $b class_ids $class]
  }
  lappend ids $id
  dict set b class_ids $class $ids
  return $id
}

proc ::fc::ensure_net {bVar full} {
  upvar 1 $bVar b
  set id "net:$full"
  if {[dict exists $b objects $id]} { return $id }
  return [::fc::add_object b net $full [dict create \
    fanout 0 drivers 0 connections [list] net_type signal]]
}

proc ::fc::connect_net {bVar netid endpoint} {
  upvar 1 $bVar b
  dict set b objects $endpoint net $netid
  set conns [dict get $b objects $netid connections]
  if {[lsearch -exact $conns $endpoint] < 0} {
    lappend conns $endpoint
    dict set b objects $netid connections $conns
  }
}

proc ::fc::norm_dir {dir} {
  switch -- $dir {
    input - in { return in }
    output - out { return out }
    inout { return inout }
    default { return $dir }
  }
}

proc ::fc::module_exists {name} {
  set lib [::fc::lib_get]
  return [dict exists $lib modules $name]
}

proc ::fc::module_get {name} {
  set lib [::fc::lib_get]
  if {![dict exists $lib modules $name]} {
    ::fc::fail "module '$name' is not loaded (VER-004)"
  }
  return [dict get $lib modules $name]
}

proc ::fc::lib_cell {name} {
  set lib [::fc::lib_get]
  if {![dict exists $lib cells $name]} { return "" }
  return [dict get $lib cells $name]
}

proc ::fc::conn_lookup {conns pin} {
  foreach c $conns {
    if {[dict get $c pin] eq $pin} {
      return [dict get $c net]
    }
  }
  return ""
}

proc ::fc::hier_net_name {path local} {
  if {$local eq ""} { return "" }
  if {$path eq ""} { return $local }
  return "$path/$local"
}

proc ::fc::finalize_nets {bVar} {
  upvar 1 $bVar b
  foreach id [::fc::class_ids_in $b net] {
    set fo 0
    set dr 0
    foreach cid [dict get $b objects $id connections] {
      set dir [dict get $b objects $cid direction]
      set cls [dict get $b objects $cid object_class]
      if {$cls eq "port"} {
        if {$dir eq "in"} { incr dr } else { incr fo }
      } elseif {$dir eq "in" || $dir eq "inout"} {
        incr fo
      } else {
        incr dr
      }
    }
    dict set b objects $id fanout $fo
    dict set b objects $id drivers $dr
  }
}

proc ::fc::rollup_area {bVar} {
  upvar 1 $bVar b
  set cells [::fc::class_ids_in $b cell]
  set ranked [list]
  foreach id $cells {
    set full [dict get $b objects $id full_name]
    lappend ranked [list [llength [split $full /]] $id]
  }
  set ranked [lsort -integer -decreasing -index 0 $ranked]
  foreach pair $ranked {
    set id [lindex $pair 1]
    if {[dict get $b objects $id is_hierarchical] eq "false"} { continue }
    set full [dict get $b objects $id full_name]
    set sum 0.0
    foreach cid $cells {
      if {[dict get $b objects $cid parent] eq $full} {
        set sum [expr {$sum + [dict get $b objects $cid area]}]
      }
    }
    dict set b objects $id area $sum
  }
}

proc ::fc::elaborate_module {bVar modname path} {
  upvar 1 $bVar b
  set mod [::fc::module_get $modname]
  set netnames [list]
  foreach p [dict get $mod ports] {
    lappend netnames [dict get $p name]
  }
  foreach w [dict get $mod wires] {
    lappend netnames [dict get $w name]
  }
  foreach inst [dict get $mod insts] {
    foreach c [dict get $inst conns] {
      set nn [dict get $c net]
      if {$nn ne ""} { lappend netnames $nn }
    }
  }
  foreach nn [lsort -unique $netnames] {
    ::fc::ensure_net b [::fc::hier_net_name $path $nn]
  }
  if {$path eq ""} {
    foreach p [dict get $mod ports] {
      set pname [dict get $p name]
      set dir [::fc::norm_dir [dict get $p direction]]
      set pid [::fc::add_object b port $pname [dict create \
        direction $dir net "net:$pname" is_clock false side "" offset ""]]
      ::fc::connect_net b "net:$pname" $pid
    }
  } else {
    foreach p [dict get $mod ports] {
      set pname [dict get $p name]
      set pinid "pin:$path/$pname"
      if {[dict exists $b objects $pinid]} {
        set existing ""
        if {[dict exists $b objects $pinid net]} {
          set existing [dict get $b objects $pinid net]
        }
        ::fc::connect_net b "net:[::fc::hier_net_name $path $pname]" $pinid
        if {$existing ne ""} {
          dict set b objects $pinid net $existing
        }
      }
    }
  }
  foreach inst [dict get $mod insts] {
    set iname [dict get $inst name]
    set ref [dict get $inst ref]
    set full [::fc::hier_net_name $path $iname]
    set conns [dict get $inst conns]
    if {[::fc::module_exists $ref]} {
      set childmod [::fc::module_get $ref]
      set cid [::fc::add_object b cell $full [dict create \
        ref_name $ref \
        is_hierarchical true \
        is_sequential false \
        is_placed false \
        is_pg false \
        area 0 \
        leakage 0 \
        parent $path \
        x "" y "" orientation N \
        number_of_pins [llength [dict get $childmod ports]]]]
      foreach p [dict get $childmod ports] {
        set pname [dict get $p name]
        set dir [::fc::norm_dir [dict get $p direction]]
        set pinid [::fc::add_object b pin "$full/$pname" [dict create \
          direction $dir cell $cid net "" pin_name $pname is_pg false is_clock_pin false]]
        set mapped [::fc::conn_lookup $conns $pname]
        if {$mapped ne ""} {
          set pnet [::fc::hier_net_name $path $mapped]
          ::fc::ensure_net b $pnet
          ::fc::connect_net b "net:$pnet" $pinid
        }
      }
      foreach c $conns {
        set known 0
        foreach p [dict get $childmod ports] {
          if {[dict get $p name] eq [dict get $c pin]} { set known 1 }
        }
        if {!$known} {
          ::fc::fail "pin '[dict get $c pin]' is not a port of $ref ($full) (LINK-002)"
        }
      }
      ::fc::elaborate_module b $ref $full
    } else {
      set lcell [::fc::lib_cell $ref]
      if {$lcell eq ""} {
        ::fc::fail "cannot resolve reference '$ref' for instance '$full' (LINK-001)"
      }
      set is_seq [expr {[dict get $lcell seq] eq "true" ? "true" : "false"}]
      set pins [dict get $lcell pins]
      set cid [::fc::add_object b cell $full [dict create \
        ref_name $ref \
        is_hierarchical false \
        is_sequential $is_seq \
        is_placed false \
        is_pg false \
        area [dict get $lcell area] \
        leakage [dict get $lcell leakage] \
        parent $path \
        x "" y "" orientation N \
        number_of_pins [expr {[llength $pins] + 2}]]]
      foreach p $pins {
        set pname [dict get $p name]
        set dir [dict get $p direction]
        set is_ck [expr {$pname in {CK CLK CP} ? "true" : "false"}]
        set pinid [::fc::add_object b pin "$full/$pname" [dict create \
          direction $dir cell $cid net "" pin_name $pname is_pg false is_clock_pin $is_ck]]
        set mapped [::fc::conn_lookup $conns $pname]
        if {$mapped ne ""} {
          set pnet [::fc::hier_net_name $path $mapped]
          ::fc::ensure_net b $pnet
          ::fc::connect_net b "net:$pnet" $pinid
        }
      }
      foreach {pname dir pgtype} {VDD in power VSS in ground} {
        set pinid [::fc::add_object b pin "$full/$pname" [dict create \
          direction $dir cell $cid net "" pin_name $pname is_pg true is_clock_pin false pg_type $pgtype]]
      }
      foreach c $conns {
        set known 0
        foreach p $pins {
          if {[dict get $p name] eq [dict get $c pin]} { set known 1 }
        }
        if {!$known} {
          ::fc::fail "pin '[dict get $c pin]' is not a pin of $ref ($full) (LINK-002)"
        }
      }
    }
  }
}

proc ::fc::count_cells {b hierarchical} {
  set n 0
  foreach id [::fc::class_ids_in $b cell] {
    set is_h [dict get $b objects $id is_hierarchical]
    if {$hierarchical eq "any" || ($hierarchical eq "leaf" && $is_h eq "false") || ($hierarchical eq "hier" && $is_h eq "true")} {
      incr n
    }
  }
  return $n
}

proc ::fc::strip_comments {text} {
  set text [string map {\r ""} $text]
  regsub -all {(?s)/\*.*?\*/} $text "" text
  regsub -all {//[^\n]*} $text "" text
  return $text
}

proc ::fc::vlog_split_semi {body} {
  set out [list]
  set buf ""
  set depth 0
  set n [string length $body]
  for {set i 0} {$i < $n} {incr i} {
    set c [string index $body $i]
    if {$c eq "("} { incr depth }
    if {$c eq ")"} { incr depth -1 }
    if {$c eq ";" && $depth == 0} {
      lappend out $buf
      set buf ""
    } else {
      append buf $c
    }
  }
  if {[string trim $buf] ne ""} {
    ::fc::fail "missing semicolon near '[string range [string trim $buf] 0 60]' (VER-005)"
  }
  return $out
}

proc ::fc::vlog_decl_names {kind rest} {
  set rest [string trim $rest]
  set msb ""
  set lsb ""
  if {[regexp {^\[(\d+)\s*:\s*(\d+)\]\s*(.*)$} $rest -> msb lsb rest]} {
    set rest [string trim $rest]
  }
  set out [list]
  foreach n [split $rest ,] {
    set n [string trim $n]
    if {$n eq ""} continue
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $n]} {
      ::fc::fail "unsupported declaration name '$n' (VER-006)"
    }
    if {$msb eq ""} {
      lappend out [dict create name $n direction $kind]
    } else {
      set lo [expr {min($msb, $lsb)}]
      set hi [expr {max($msb, $lsb)}]
      for {set i $hi} {$i >= $lo} {incr i -1} {
        lappend out [dict create name "${n}_${i}" direction $kind]
      }
    }
  }
  return $out
}

proc ::fc::vlog_conns {text} {
  set text [string trim $text]
  set result [list]
  set n [string length $text]
  set i 0
  while {$i < $n} {
    set c [string index $text $i]
    if {$c eq "," || [string is space $c]} {
      incr i
      continue
    }
    if {$c ne "."} {
      ::fc::fail "expected .pin(net) near '[string range $text $i [expr {$i + 40}]]' (VER-007)"
    }
    incr i
    if {![regexp -start $i -indices {[A-Za-z_][A-Za-z0-9_]*} $text mr]} {
      ::fc::fail "expected a pin name (VER-007)"
    }
    set pin [string range $text {*}$mr]
    set i [expr {[lindex $mr 1] + 1}]
    while {$i < $n && [string is space [string index $text $i]]} { incr i }
    if {$i >= $n || [string index $text $i] ne "("} {
      ::fc::fail "expected '(' after .$pin (VER-007)"
    }
    incr i
    set j $i
    set depth 0
    while {$j < $n} {
      set c [string index $text $j]
      if {$c eq "("} { incr depth }
      if {$c eq ")"} {
        if {$depth == 0} { break }
        incr depth -1
      }
      incr j
    }
    if {$j >= $n} {
      ::fc::fail "unterminated connection for .$pin (VER-007)"
    }
    set net [string trim [string range $text $i [expr {$j - 1}]]]
    if {$net ne "" && ![regexp {^[A-Za-z_][A-Za-z0-9_]*(\[[0-9]+\])?$} $net]} {
      ::fc::fail "unsupported net expression '$net' (VER-008)"
    }
    lappend result [dict create pin $pin net $net]
    set i [expr {$j + 1}]
  }
  return $result
}

proc ::fc::vlog_parse_module {chunk path} {
  regsub {(?w)\mendmodule\M\s*$} $chunk "" chunk
  set chunk [string trim $chunk]
  if {![regexp {(?s)^module\s+([A-Za-z_][A-Za-z0-9_]*)\s*(.*)$} $chunk -> name body]} {
    ::fc::fail "bad module header in $path (VER-009)"
  }
  set body [string trim $body]
  if {[string index $body 0] eq "("} {
    set depth 0
    set n [string length $body]
    set i 0
    for {} {$i < $n} {incr i} {
      set c [string index $body $i]
      if {$c eq "("} { incr depth }
      if {$c eq ")"} {
        incr depth -1
        if {$depth == 0} {
          incr i
          break
        }
      }
    }
    set body [string trim [string range $body $i end]]
    if {[string index $body 0] eq ";"} {
      set body [string trim [string range $body 1 end]]
    }
  }
  set ports [list]
  set wires [list]
  set insts [list]
  foreach st [::fc::vlog_split_semi $body] {
    set st [string trim $st]
    if {$st eq ""} continue
    if {[regexp {(?s)^(input|output|inout)(\s+.*)$} $st -> dir rest]} {
      lappend ports {*}[::fc::vlog_decl_names $dir $rest]
      continue
    }
    if {[regexp {(?s)^wire(\s+.*)$} $st -> rest]} {
      lappend wires {*}[::fc::vlog_decl_names wire $rest]
      continue
    }
    if {[regexp {(?s)^([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\((.*)\)\s*$} $st -> ref iname conns]} {
      lappend insts [dict create ref $ref name $iname conns [::fc::vlog_conns $conns]]
      continue
    }
    ::fc::fail "unsupported statement in module $name: [string range $st 0 80] (VER-010)"
  }
  return [dict create name $name ports $ports wires $wires insts $insts]
}

proc ::fc::vlog_modules {text path} {
  set text [::fc::strip_comments $text]
  set modules [list]
  set offset 0
  while {[regexp -indices -start $offset {(?w)\mmodule\M} $text found]} {
    set start [lindex $found 0]
    if {![regexp -indices -start $start {(?w)\mendmodule\M} $text endm]} {
      ::fc::fail "unterminated module in $path (VER-002)"
    }
    set stop [lindex $endm 1]
    set chunk [string range $text $start $stop]
    lappend modules [::fc::vlog_parse_module $chunk $path]
    set offset [expr {$stop + 1}]
  }
  if {[llength $modules] == 0} {
    ::fc::fail "no modules found in $path (VER-003)"
  }
  return $modules
}

proc ::fc::parse_celllib {text path} {
  set libname "std"
  set cells [dict create]
  set lineno 0
  foreach line [split $text \n] {
    incr lineno
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} continue
    if {[regexp {^library\s+(\S+)\s*$} $line -> libname]} continue
    if {![regexp {^cell\s+(\S+)\s+area\s+(\S+)\s+leakage\s+(\S+)\s+seq\s+(\S+)\s+pins\s+\{(.+)\}\s*$} $line -> name area lkg seq pins]} {
      ::fc::fail "bad celllib line $lineno in $path: $line (LIB-010)"
    }
    if {![string is double -strict $area] || ![string is double -strict $lkg]} {
      ::fc::fail "area and leakage must be numbers for cell $name (LIB-010)"
    }
    if {$seq ni {true false}} {
      ::fc::fail "seq must be true or false for cell $name (LIB-010)"
    }
    set pinlist [list]
    set ps [regexp -all -inline {\S+} $pins]
    if {[llength $ps] % 2 != 0} {
      ::fc::fail "pins for $name must be name/direction pairs (LIB-010)"
    }
    foreach {pn pd} $ps {
      if {$pd ni {in out inout}} {
        ::fc::fail "pin $name/$pn has direction '$pd' (LIB-010)"
      }
      lappend pinlist [dict create name $pn direction $pd]
    }
    dict set cells $name [dict create name $name area $area leakage $lkg seq $seq pins $pinlist library $libname]
  }
  if {[dict size $cells] == 0} {
    ::fc::fail "no cells in $path (LIB-010)"
  }
  return [dict create name $libname cells $cells]
}

proc ::fc::parse_tech {text path} {
  set tech [dict create \
    name "" \
    units [dict create] \
    site_name core \
    site_w 0.2 \
    site_h 1.4 \
    layers [list]]
  foreach line [split $text \n] {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} continue
    if {[regexp {^technology\s+(\S+)\s*$} $line -> name]} {
      dict set tech name $name
      continue
    }
    if {[regexp {^unit\s+(\S+)\s+(\S+)\s*$} $line -> key value]} {
      dict set tech units $key $value
      continue
    }
    if {[regexp {^site\s+(\S+)\s+(\S+)\s+(\S+)\s*$} $line -> sname w h]} {
      dict set tech site_name $sname
      dict set tech site_w $w
      dict set tech site_h $h
      continue
    }
    if {[regexp {^layer\s+(\S+)\s+(\S+)\s+pitch\s+(\S+)\s*$} $line -> lname dir pitch]} {
      dict lappend tech layers [dict create name $lname direction $dir pitch $pitch]
      continue
    }
    ::fc::fail "bad technology line in $path: $line (TECH-001)"
  }
  if {[dict get $tech name] eq ""} {
    ::fc::fail "technology file $path has no name (TECH-001)"
  }
  return $tech
}

proc ::fc::read_text_file {path} {
  if {![file exists $path]} {
    ::fc::fail "file not found: $path (IO-001)"
  }
  set fh [open $path r]
  set text [read $fh]
  close $fh
  return $text
}

proc ::fc::rebuild_lib_objects {} {
  variable db
  set lib [::fc::lib_get]
  set objects [dict create]
  set lname [dict get $lib lib_label]
  set lid "lib:$lname"
  dict set objects $lid [dict create \
    object_class lib full_name $lname name $lname source [dict get $lib path]]
  dict for {cname cell} [dict get $lib cells] {
    set full "$lname/$cname"
    set id "lib_cell:$full"
    dict set objects $id [dict create \
      object_class lib_cell \
      full_name $full \
      name $cname \
      library_name $lname \
      area [dict get $cell area] \
      leakage [dict get $cell leakage] \
      is_sequential [dict get $cell seq] \
      dont_touch false]
  }
  dict set db lib_objects $objects
}

proc ::fc::empty_lib {name path} {
  return [dict create \
    name $name \
    lib_label $name \
    path $path \
    tech [dict create] \
    cells [dict create] \
    modules [dict create] \
    verilog_text "" \
    block_names [list]]
}

proc ::fc::lib_meta {lib} {
  return [dict create \
    name [dict get $lib name] \
    lib_label [dict get $lib lib_label] \
    path [dict get $lib path] \
    tech [dict get $lib tech] \
    cells [dict get $lib cells] \
    modules [dict get $lib modules] \
    verilog_text [dict get $lib verilog_text] \
    block_names [dict get $lib block_names]]
}

proc ::fc::write_snapshot {path varname value} {
  set dir [file dirname $path]
  if {![file isdirectory $dir]} {
    file mkdir $dir
  }
  set fh [open $path w]
  puts $fh "# fc_shell practice snapshot"
  puts $fh "set $varname [list $value]"
  close $fh
}

proc ::fc::write_lib_meta {} {
  set lib [::fc::lib_get]
  ::fc::write_snapshot [file join [dict get $lib path] lib.info] \
    ::fc::loaded_lib [::fc::lib_meta $lib]
}

proc ::fc::write_block_file {b} {
  set lib [::fc::lib_get]
  set path [file join [dict get $lib path] "[dict get $b name].block"]
  ::fc::write_snapshot $path ::fc::loaded_block $b
  set names [dict get $lib block_names]
  if {[lsearch -exact $names [dict get $b name]] < 0} {
    lappend names [dict get $b name]
    dict set lib block_names $names
    ::fc::lib_set $lib
  }
}

proc ::fc::open_block_named {name} {
  variable db
  set lib [::fc::lib_get]
  if {![dict exists $db blocks $name]} {
    set path [file join [dict get $lib path] "$name.block"]
    if {![file exists $path]} {
      ::fc::fail "block '$name' is not in library [dict get $lib name] (DES-004)"
    }
    unset -nocomplain ::fc::loaded_block
    source $path
    dict set db blocks $name $::fc::loaded_block
    unset ::fc::loaded_block
  }
  dict set db current_block $name
  return $name
}

proc ::fc::make_block {name} {
  variable db
  set lib [::fc::lib_get]
  if {[dict exists $db blocks $name]} {
    ::fc::fail "block '$name' already exists (DES-005)"
  }
  set b [::fc::new_block $name]
  dict set db blocks $name $b
  dict set db current_block $name
  set names [dict get $lib block_names]
  if {[lsearch -exact $names $name] < 0} {
    lappend names $name
    dict set lib block_names $names
    ::fc::lib_set $lib
  }
  return $name
}

# --- user commands ----------------------------------------------------------

proc create_lib {args} {
  variable ::fc::db
  set techfile ""
  set reflibs [list]
  set path ""
  set xs $args
  while {[llength $xs]} {
    set a [lindex $xs 0]
    if {![string match -* $a]} {
      if {$path ne ""} {
        ::fc::fail "unexpected argument '$a' (LIB-001)"
      }
      set path $a
      set xs [lrange $xs 1 end]
      continue
    }
    switch -- $a {
      -technology {
        set xs [lrange $xs 1 end]
        set techfile [::fc::take xs]
      }
      -ref_libs {
        set xs [lrange $xs 1 end]
        set reflibs [::fc::as_list [::fc::take xs]]
      }
      default { ::fc::fail "unknown option '$a' for create_lib (LIB-001)" }
    }
  }
  if {$techfile eq "" || [llength $reflibs] == 0 || $path eq ""} {
    ::fc::fail "usage: create_lib -technology techfile -ref_libs libs path (LIB-001)"
  }
  if {[::fc::has_lib]} {
    ::fc::fail "library '[::fc::current_lib_name]' is open; close_lib first (LIB-002)"
  }
  if {[file exists $path]} {
    ::fc::fail "library already exists: $path (LIB-003). Delete it or pick a new path."
  }
  set name [file rootname [file tail $path]]
  file mkdir $path
  set lib [::fc::empty_lib $name $path]
  set tech [::fc::parse_tech [::fc::read_text_file $techfile] $techfile]
  dict set lib tech $tech
  foreach rf $reflibs {
    set parsed [::fc::parse_celllib [::fc::read_text_file $rf] $rf]
    dict set lib lib_label [dict get $parsed name]
    dict for {cname cell} [dict get $parsed cells] {
      if {[dict exists $lib cells $cname]} {
        ::fc::warn_msg LIB-011 "replacing cell $cname from $rf"
      }
      dict set lib cells $cname $cell
    }
  }
  dict set db libs $name $lib
  dict set db current_lib $name
  ::fc::rebuild_lib_objects
  ::fc::write_lib_meta
  ::fc::info_msg LIB-100 "created library $name at $path ([dict size [dict get $lib cells]] reference cells)"
  return $name
}

proc open_lib {path} {
  variable ::fc::db
  if {[::fc::has_lib]} {
    ::fc::fail "library '[::fc::current_lib_name]' is open; close_lib first (LIB-002)"
  }
  set info [file join $path lib.info]
  if {![file exists $info]} {
    ::fc::fail "not a practice library (missing lib.info): $path (LIB-005)"
  }
  unset -nocomplain ::fc::loaded_lib
  source $info
  set lib $::fc::loaded_lib
  unset ::fc::loaded_lib
  set name [dict get $lib name]
  dict set db libs $name $lib
  dict set db current_lib $name
  dict set db blocks [dict create]
  dict set db current_block ""
  ::fc::rebuild_lib_objects
  foreach bname [dict get $lib block_names] {
    set bpath [file join $path "$bname.block"]
    if {![file exists $bpath]} { continue }
    unset -nocomplain ::fc::loaded_block
    source $bpath
    dict set db blocks $bname $::fc::loaded_block
    unset ::fc::loaded_block
    dict set db current_block $bname
  }
  ::fc::info_msg LIB-101 "opened library $name"
  return $name
}

proc save_lib {args} {
  ::fc::require_lib
  set lib [::fc::lib_get]
  variable ::fc::db
  foreach bname [dict keys [dict get $db blocks]] {
    set b [dict get $db blocks $bname]
    dict set b dirty 0
    dict set db blocks $bname $b
    ::fc::write_block_file $b
  }
  ::fc::write_lib_meta
  ::fc::info_msg LIB-102 "saved library [dict get $lib name]"
  return ""
}

proc close_lib {args} {
  variable ::fc::db
  set force 0
  foreach a $args {
    switch -- $a {
      -force { set force 1 }
      default { ::fc::fail "unknown option '$a' for close_lib (LIB-006)" }
    }
  }
  if {![::fc::has_lib]} {
    ::fc::warn_msg LIB-007 "no library is open"
    return ""
  }
  if {!$force} {
    dict for {name b} [dict get $db blocks] {
      if {[dict get $b dirty]} {
        ::fc::fail "library has unsaved changes; save_lib or close_lib -force (LIB-004)"
      }
    }
  }
  set name [dict get $db current_lib]
  dict set db current_lib ""
  dict set db current_block ""
  dict set db libs [dict create]
  dict set db blocks [dict create]
  dict set db lib_objects [dict create]
  ::fc::info_msg LIB-103 "closed library $name"
  return ""
}

proc current_lib {args} {
  if {[llength $args] == 0} {
    ::fc::require_lib
    return [::fc::current_lib_name]
  }
  ::fc::fail "current_lib only returns the open library on this platform (LIB-008)"
}

proc report_lib {args} {
  set lib [::fc::lib_get]
  puts "Library : [dict get $lib name]"
  puts "Path    : [dict get $lib path]"
  puts "Tech    : [dict get [dict get $lib tech] name]"
  puts "Cells   : [dict size [dict get $lib cells]]"
  puts "Modules : [join [lsort [dict keys [dict get $lib modules]]] {, }]"
  variable ::fc::db
  puts "Blocks  : [join [dict keys [dict get $db blocks]] {, }]"
  return ""
}

proc list_blocks {args} {
  ::fc::require_lib
  variable ::fc::db
  set cur [dict get $db current_block]
  foreach name [lsort [dict keys [dict get $db blocks]]] {
    set mark [expr {$name eq $cur ? "*" : " "}]
    set stage [dict get [dict get $db blocks $name] stage]
    puts [format "%s %-24s %s" $mark $name $stage]
  }
  return ""
}

proc create_block {name} {
  ::fc::make_block $name
  ::fc::info_msg DES-100 "created block $name"
  return $name
}

proc open_block {name} {
  set name [::fc::open_block_named $name]
  ::fc::info_msg DES-101 "current block is $name"
  return $name
}

proc current_block {args} {
  if {[llength $args] == 0} {
    return [::fc::current_block_name]
  }
  if {[llength $args] != 1} {
    ::fc::fail "usage: current_block ?name? (DES-006)"
  }
  return [open_block [lindex $args 0]]
}

proc save_block {args} {
  set b [::fc::block_get]
  dict set b dirty 0
  ::fc::block_set $b
  set b [::fc::block_get]
  ::fc::write_block_file $b
  ::fc::write_lib_meta
  ::fc::info_msg DES-102 "saved block [dict get $b name]"
  return ""
}

proc close_block {args} {
  variable ::fc::db
  set force 0
  foreach a $args {
    if {$a eq "-force"} { set force 1 } else {
      ::fc::fail "unknown option '$a' for close_block (DES-007)"
    }
  }
  if {![::fc::has_block]} { return "" }
  set b [::fc::block_get]
  if {!$force && [dict get $b dirty]} {
    ::fc::fail "block has unsaved changes; save_block or close_block -force (DES-008)"
  }
  set name [dict get $b name]
  dict unset db blocks $name
  dict set db current_block ""
  set lib [::fc::lib_get]
  set names [dict get $lib block_names]
  set i [lsearch -exact $names $name]
  if {$i >= 0} {
    dict set lib block_names [lreplace $names $i $i]
    ::fc::lib_set $lib
  }
  ::fc::info_msg DES-103 "closed block $name"
  return ""
}

proc copy_block {args} {
  set from ""
  set to ""
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -from { set from [::fc::take xs] }
      -to { set to [::fc::take xs] }
      default { ::fc::fail "unknown option '$a' for copy_block (DES-009)" }
    }
  }
  if {$from eq "" || $to eq ""} {
    ::fc::fail "usage: copy_block -from name -to name (DES-009)"
  }
  variable ::fc::db
  if {![dict exists $db blocks $from]} {
    open_block $from
  }
  if {[dict exists $db blocks $to]} {
    ::fc::fail "block '$to' already exists (DES-005)"
  }
  set b [dict get $db blocks $from]
  dict set b name $to
  dict set b dirty 1
  dict set db blocks $to $b
  set lib [::fc::lib_get]
  dict lappend lib block_names $to
  ::fc::lib_set $lib
  ::fc::info_msg DES-104 "copied block $from to $to"
  return $to
}

proc read_verilog {args} {
  ::fc::require_lib
  set top ""
  set files [list]
  set xs $args
  while {[llength $xs]} {
    set a [lindex $xs 0]
    if {$a eq "-top"} {
      set xs [lrange $xs 1 end]
      set top [::fc::take xs]
    } elseif {[string match -* $a]} {
      ::fc::fail "unknown option '$a' for read_verilog (VER-001)"
    } else {
      lappend files {*}[::fc::as_list $a]
      set xs [lrange $xs 1 end]
    }
  }
  if {[llength $files] == 0} {
    ::fc::fail "usage: read_verilog ?-top name? file ?file ...? (VER-001)"
  }
  set lib [::fc::lib_get]
  foreach f $files {
    set text [::fc::read_text_file $f]
    append text "\n"
    dict append lib verilog_text $text
    foreach m [::fc::vlog_modules $text $f] {
      set mname [dict get $m name]
      dict set lib modules $mname $m
      ::fc::info_msg VER-100 "read module $mname ([llength [dict get $m insts]] instances) from $f"
    }
  }
  ::fc::lib_set $lib
  if {$top ne ""} {
    if {![::fc::module_exists $top]} {
      ::fc::fail "top module '$top' was not found (VER-004)"
    }
    variable ::fc::db
    if {[dict exists $db blocks $top]} {
      dict set db current_block $top
      set b [dict get $db blocks $top]
      if {[dict get $b linked]} {
        ::fc::warn_msg VER-011 "block $top is already linked; read more Verilog then link_block to rebuild"
      }
    } else {
      ::fc::make_block $top
    }
    ::fc::info_msg VER-101 "current block set to $top"
  }
  return $top
}

proc link_block {args} {
  set b [::fc::block_get]
  set top [dict get $b top]
  if {![::fc::module_exists $top]} {
    ::fc::fail "top module '$top' is not loaded (LINK-003)"
  }
  if {[dict get $b linked]} {
    ::fc::warn_msg LINK-004 "relinking discards constraints, floorplan, and attributes"
  }
  set fresh [::fc::new_block [dict get $b name]]
  dict set fresh top $top
  ::fc::elaborate_module fresh $top ""
  ::fc::finalize_nets fresh
  ::fc::rollup_area fresh
  ::fc::add_object fresh scenario func [dict create active true]
  dict set fresh current_scenario func
  dict set fresh linked 1
  dict set fresh stage linked
  dict set fresh dirty 1
  ::fc::block_set $fresh
  set nleaf [::fc::count_cells $fresh leaf]
  set nhier [::fc::count_cells $fresh hier]
  ::fc::info_msg LINK-100 "linked $top ($nleaf leaf cells, $nhier hierarchical cells)"
  return [dict get $fresh name]
}

proc write_verilog {args} {
  set hier "all"
  set file ""
  set xs $args
  while {[llength $xs]} {
    set a [lindex $xs 0]
    if {$a eq "-hierarchy"} {
      set xs [lrange $xs 1 end]
      set hier [::fc::take xs]
    } elseif {[string match -* $a]} {
      ::fc::fail "unknown option '$a' for write_verilog (VER-012)"
    } else {
      set file $a
      set xs [lrange $xs 1 end]
    }
  }
  if {$file eq ""} {
    ::fc::fail "usage: write_verilog ?-hierarchy all? file (VER-012)"
  }
  set lib [::fc::lib_get]
  set dir [file dirname $file]
  if {$dir ne "." && ![file isdirectory $dir]} { file mkdir $dir }
  set fh [open $file w]
  puts $fh "// written by fc_shell practice platform"
  puts -nonewline $fh [dict get $lib verilog_text]
  close $fh
  ::fc::info_msg VER-102 "wrote verilog $file"
  return ""
}

proc ::fc::add_constraint {kind data} {
  set b [::fc::block_get]
  set cs [dict get $b constraints]
  lappend cs [dict merge [dict create kind $kind] $data]
  dict set b constraints $cs
  dict set b dirty 1
  ::fc::block_set $b
}

proc ::fc::object_names_of {collection} {
  if {$collection eq ""} { return [list] }
  return [::fc::collection_names $collection]
}

proc create_clock {args} {
  ::fc::require_linked
  set name ""
  set period ""
  set waveform ""
  set sources ""
  set xs $args
  while {[llength $xs]} {
    set a [lindex $xs 0]
    switch -- $a {
      -name {
        set xs [lrange $xs 1 end]
        set name [::fc::take xs]
      }
      -period {
        set xs [lrange $xs 1 end]
        set period [::fc::take xs]
      }
      -waveform {
        set xs [lrange $xs 1 end]
        set waveform [::fc::take xs]
      }
      default {
        if {[string match -* $a]} {
          ::fc::fail "unknown option '$a' for create_clock (SDC-001)"
        }
        set sources $a
        set xs [lrange $xs 1 end]
      }
    }
  }
  if {$name eq "" || $period eq ""} {
    ::fc::fail "usage: create_clock -name name -period ns ?objects? (SDC-001)"
  }
  if {![string is double -strict $period] || $period <= 0} {
    ::fc::fail "clock period must be a positive number (SDC-001)"
  }
  if {$waveform eq ""} {
    set waveform [list 0 [expr {$period / 2.0}]]
  }
  set b [::fc::block_get]
  set id "clock:$name"
  if {[dict exists $b objects $id]} {
    dict unset b objects $id
    set ids [dict get $b class_ids clock]
    set i [lsearch -exact $ids $id]
    if {$i >= 0} {
      dict set b class_ids clock [lreplace $ids $i $i]
    }
    ::fc::block_set $b
    ::fc::warn_msg SDC-002 "replacing clock $name"
  }
  set src_names [list]
  if {$sources ne ""} {
    set src_names [::fc::collection_names $sources]
    foreach sid [::fc::collection_items $sources] {
      ::fc::set_attr $sid is_clock true
    }
  }
  set b [::fc::block_get]
  ::fc::add_object b clock $name [dict create \
    period $period \
    waveform $waveform \
    sources $src_names \
    active true]
  ::fc::block_set $b
  ::fc::info_msg SDC-100 "created clock $name period $period"
  return $name
}

proc ::fc::parse_delay_cmd {args} {
  set clock ""
  set rest [list]
  set xs $args
  while {[llength $xs]} {
    set a [lindex $xs 0]
    if {$a eq "-clock"} {
      set xs [lrange $xs 1 end]
      set clock [::fc::take xs]
    } elseif {[string match -* $a]} {
      ::fc::fail "unknown option '$a' (SDC-003)"
    } else {
      lappend rest $a
      set xs [lrange $xs 1 end]
    }
  }
  if {[llength $rest] != 2} {
    ::fc::fail "expected delay_value and object collection (SDC-003)"
  }
  return [list $clock [lindex $rest 0] [lindex $rest 1]]
}

proc set_input_delay {args} {
  ::fc::require_linked
  lassign [::fc::parse_delay_cmd {*}$args] clock value objects
  ::fc::add_constraint input_delay [dict create clock $clock value $value objects [::fc::object_names_of $objects]]
  return ""
}

proc set_output_delay {args} {
  ::fc::require_linked
  lassign [::fc::parse_delay_cmd {*}$args] clock value objects
  ::fc::add_constraint output_delay [dict create clock $clock value $value objects [::fc::object_names_of $objects]]
  return ""
}

proc set_load {value objects} {
  ::fc::require_linked
  ::fc::add_constraint set_load [dict create value $value objects [::fc::object_names_of $objects]]
  return ""
}

proc set_false_path {args} {
  ::fc::require_linked
  set from ""
  set to ""
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -from { set from [::fc::take xs] }
      -to { set to [::fc::take xs] }
      default { ::fc::fail "unknown option '$a' for set_false_path (SDC-004)" }
    }
  }
  ::fc::add_constraint false_path [dict create from [::fc::object_names_of $from] to [::fc::object_names_of $to]]
  return ""
}

proc set_max_delay {args} {
  ::fc::require_linked
  set from ""
  set to ""
  set value ""
  set xs $args
  while {[llength $xs]} {
    set a [lindex $xs 0]
    switch -- $a {
      -from { set xs [lrange $xs 1 end]; set from [::fc::take xs] }
      -to { set xs [lrange $xs 1 end]; set to [::fc::take xs] }
      default {
        if {[string match -* $a]} {
          ::fc::fail "unknown option '$a' for set_max_delay (SDC-005)"
        }
        set value $a
        set xs [lrange $xs 1 end]
      }
    }
  }
  if {$value eq ""} {
    ::fc::fail "usage: set_max_delay value ?-from col? ?-to col? (SDC-005)"
  }
  ::fc::add_constraint max_delay [dict create value $value from [::fc::object_names_of $from] to [::fc::object_names_of $to]]
  return ""
}

proc group_path {args} {
  ::fc::require_linked
  set name ""
  set from ""
  set to ""
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -name { set name [::fc::take xs] }
      -from { set from [::fc::take xs] }
      -to { set to [::fc::take xs] }
      default { ::fc::fail "unknown option '$a' for group_path (SDC-006)" }
    }
  }
  if {$name eq ""} {
    ::fc::fail "usage: group_path -name name ?-from col? ?-to col? (SDC-006)"
  }
  ::fc::add_constraint group_path [dict create name $name from [::fc::object_names_of $from] to [::fc::object_names_of $to]]
  return ""
}

proc read_sdc {file} {
  ::fc::require_linked
  if {![file exists $file]} {
    ::fc::fail "file not found: $file (IO-001)"
  }
  ::fc::info_msg SDC-101 "reading $file"
  uplevel #0 [list source $file]
  return ""
}

proc write_sdc {file} {
  ::fc::require_linked
  set b [::fc::block_get]
  set dir [file dirname $file]
  if {$dir ne "." && ![file isdirectory $dir]} { file mkdir $dir }
  set fh [open $file w]
  puts $fh "# written by fc_shell practice platform"
  foreach id [::fc::class_ids_in $b clock] {
    set o [dict get $b objects $id]
    set srcs [dict get $o sources]
    set src_txt ""
    if {[llength $srcs] > 0} {
      set src_txt " \[get_ports \{[join $srcs]\}]"
    }
    puts $fh "create_clock -name [dict get $o name] -period [dict get $o period]$src_txt"
  }
  foreach c [dict get $b constraints] {
    puts $fh "# [dict get $c kind] [dict get $c]"
  }
  close $fh
  ::fc::info_msg SDC-102 "wrote $file"
  return ""
}

proc create_scenario {name} {
  ::fc::require_linked
  set b [::fc::block_get]
  if {[dict exists $b objects "scenario:$name"]} {
    ::fc::fail "scenario '$name' already exists (SCN-001)"
  }
  ::fc::add_object b scenario $name [dict create active true]
  ::fc::block_set $b
  ::fc::info_msg SCN-100 "created scenario $name"
  return $name
}

proc current_scenario {args} {
  ::fc::require_linked
  set b [::fc::block_get]
  if {[llength $args] == 0} {
    return [dict get $b current_scenario]
  }
  set name [lindex $args 0]
  if {![dict exists $b objects "scenario:$name"]} {
    ::fc::fail "scenario '$name' does not exist (SCN-002)"
  }
  dict set b current_scenario $name
  dict set b dirty 1
  ::fc::block_set $b
  return $name
}

proc set_scenario_status {name args} {
  ::fc::require_linked
  set active ""
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -active { set active [::fc::take xs] }
      default { ::fc::fail "unknown option '$a' for set_scenario_status (SCN-003)" }
    }
  }
  if {$active eq ""} {
    ::fc::fail "usage: set_scenario_status name -active true|false (SCN-003)"
  }
  set id "scenario:$name"
  set b [::fc::block_get]
  if {![dict exists $b objects $id]} {
    ::fc::fail "scenario '$name' does not exist (SCN-002)"
  }
  set flag [expr {[string is true $active] ? "true" : "false"}]
  ::fc::set_attr $id active $flag
  return ""
}

proc all_scenarios {args} {
  return [::fc::query_objects scenario all_scenarios]
}

proc create_net {args} {
  ::fc::require_linked
  set kind signal
  set name ""
  set xs $args
  while {[llength $xs]} {
    set a [lindex $xs 0]
    switch -- $a {
      -power { set kind power; set xs [lrange $xs 1 end]; set name [::fc::take xs] }
      -ground { set kind ground; set xs [lrange $xs 1 end]; set name [::fc::take xs] }
      default {
        if {[string match -* $a]} {
          ::fc::fail "unknown option '$a' for create_net (NET-001)"
        }
        set name $a
        set xs [lrange $xs 1 end]
      }
    }
  }
  if {$name eq ""} {
    ::fc::fail "usage: create_net ?-power|-ground? name (NET-001)"
  }
  set b [::fc::block_get]
  set id "net:$name"
  if {![dict exists $b objects $id]} {
    ::fc::ensure_net b $name
  }
  dict set b objects $id net_type $kind
  dict set b dirty 1
  ::fc::block_set $b
  ::fc::info_msg NET-100 "net $name type $kind"
  return $name
}

proc connect_pg_net {args} {
  ::fc::require_linked
  set net ""
  set pins ""
  set xs $args
  while {[llength $xs]} {
    set a [lindex $xs 0]
    switch -- $a {
      -net { set xs [lrange $xs 1 end]; set net [::fc::take xs] }
      default {
        if {[string match -* $a]} {
          ::fc::fail "unknown option '$a' for connect_pg_net (NET-002)"
        }
        set pins $a
        set xs [lrange $xs 1 end]
      }
    }
  }
  if {$net eq "" || $pins eq ""} {
    ::fc::fail "usage: connect_pg_net -net name pin_collection (NET-002)"
  }
  set b [::fc::block_get]
  if {![dict exists $b objects "net:$net"]} {
    set kind [expr {$net eq "VSS" ? "ground" : "power"}]
    ::fc::ensure_net b $net
    dict set b objects "net:$net" net_type $kind
    ::fc::block_set $b
  }
  set ids [::fc::collection_items $pins]
  set n 0
  foreach id $ids {
    if {[::fc::attr $id object_class] ne "pin"} { continue }
    set b [::fc::block_get]
    ::fc::connect_net b "net:$net" $id
    ::fc::block_set $b
    incr n
  }
  set b [::fc::block_get]
  ::fc::finalize_nets b
  ::fc::block_set $b
  ::fc::info_msg NET-101 "connected $n pins to $net"
  return ""
}

proc ::fc::query_objects {class cmd args} {
  if {$class in {lib lib_cell}} {
    return [::fc::query_lib_objects $class $cmd {*}$args]
  }
  ::fc::require_linked
  set patterns [list]
  set filter ""
  set quiet 0
  set use_re 0
  set hier 0
  set of ""
  set xs $args
  while {[llength $xs]} {
    set a [lindex $xs 0]
    switch -- $a {
      -hierarchical { set hier 1; set xs [lrange $xs 1 end] }
      -quiet { set quiet 1; set xs [lrange $xs 1 end] }
      -regexp { set use_re 1; set xs [lrange $xs 1 end] }
      -filter {
        set xs [lrange $xs 1 end]
        set filter [::fc::take xs]
      }
      -of_objects {
        set xs [lrange $xs 1 end]
        set of [::fc::take xs]
      }
      default {
        if {[string match -* $a]} {
          ::fc::fail "unknown option '$a' for $cmd (CMD-002)"
        }
        lappend patterns {*}[::fc::as_list $a]
        set xs [lrange $xs 1 end]
      }
    }
  }
  set b [::fc::block_get]
  set ids [::fc::class_ids_in $b $class]
  if {$of ne ""} {
    set ids [::fc::resolve_of $class $of $ids]
  }
  if {[llength $patterns] == 0} {
    set patterns [list "*"]
  }
  set matched [list]
  foreach id $ids {
    set full [dict get $b objects $id full_name]
    set name [dict get $b objects $id name]
    set in_scope [::fc::in_current_scope $class $full]
    set ok 0
    foreach pat $patterns {
      set slash [expr {[string first / $pat] >= 0}]
      if {$use_re} {
        if {$hier && !$slash} {
          set hit [regexp -- $pat $name]
        } elseif {$slash} {
          set hit [regexp -- $pat $full]
        } else {
          set hit [expr {$in_scope && [regexp -- $pat $name]}]
        }
      } elseif {$hier && !$slash} {
        set hit [::fc::hier_match $pat $name]
      } elseif {$slash} {
        set hit [::fc::hier_match $pat $full]
      } else {
        set hit [expr {$in_scope && [::fc::hier_match $pat $name]}]
      }
      if {$hit} { set ok 1 }
    }
    if {$ok} { lappend matched $id }
  }
  if {$filter ne ""} {
    set matched [::fc::filter_ids $matched $filter]
  }
  set rows [list]
  foreach id $matched {
    lappend rows [list [dict get $b objects $id full_name] $id]
  }
  set rows [lsort -dictionary -index 0 $rows]
  set ordered [list]
  foreach row $rows { lappend ordered [lindex $row 1] }
  if {[llength $ordered] == 0 && !$quiet} {
    ::fc::warn_msg SEL-003 "nothing matched for $cmd [join $patterns]"
  }
  return [::fc::new_collection $class $ordered]
}

proc ::fc::slash_count {full} {
  return [regsub -all {/} $full {} _discard]
}

proc ::fc::in_current_scope {class full} {
  # Pins of the current (top) scope are CELL/PIN. Other objects at top have no slash.
  # * and ? never cross '/', so a deeper object needs a hierarchical pattern or -hierarchical.
  set n [::fc::slash_count $full]
  if {$class eq "pin"} {
    return [expr {$n == 1}]
  }
  return [expr {$n == 0}]
}

proc ::fc::resolve_of {target of ids_all} {
  lassign [::fc::collection_data $of] src_class src_ids
  set b [::fc::block_get]
  set out [list]
  switch -- $target {
    pin {
      if {$src_class eq "cell"} {
        foreach id [::fc::class_ids_in $b pin] {
          if {[lsearch -exact $src_ids [dict get $b objects $id cell]] >= 0} {
            lappend out $id
          }
        }
      } elseif {$src_class eq "net"} {
        foreach nid $src_ids {
          foreach cid [dict get $b objects $nid connections] {
            if {[dict get $b objects $cid object_class] eq "pin"} {
              lappend out $cid
            }
          }
        }
      } else {
        ::fc::fail "get_pins -of_objects expects cells or nets (SEL-008)"
      }
    }
    net {
      if {$src_class eq "pin" || $src_class eq "port"} {
        foreach id $src_ids {
          set n [dict get $b objects $id net]
          if {$n ne ""} { lappend out $n }
        }
      } elseif {$src_class eq "cell"} {
        foreach id [::fc::class_ids_in $b pin] {
          if {[lsearch -exact $src_ids [dict get $b objects $id cell]] >= 0} {
            set n [dict get $b objects $id net]
            if {$n ne ""} { lappend out $n }
          }
        }
      } else {
        ::fc::fail "get_nets -of_objects expects cells, pins, or ports (SEL-008)"
      }
    }
    cell {
      if {$src_class ne "pin"} {
        ::fc::fail "get_cells -of_objects expects pins (SEL-008)"
      }
      foreach id $src_ids {
        lappend out [dict get $b objects $id cell]
      }
    }
    port {
      if {$src_class ne "net"} {
        ::fc::fail "get_ports -of_objects expects nets (SEL-008)"
      }
      foreach nid $src_ids {
        foreach cid [dict get $b objects $nid connections] {
          if {[dict get $b objects $cid object_class] eq "port"} {
            lappend out $cid
          }
        }
      }
    }
    default {
      ::fc::fail "-of_objects is not supported for $target (SEL-008)"
    }
  }
  set unique [list]
  foreach id $out {
    if {[lsearch -exact $unique $id] < 0} { lappend unique $id }
  }
  return $unique
}

proc ::fc::query_lib_objects {class cmd args} {
  ::fc::require_lib
  set patterns [list "*"]
  set quiet 0
  set filter ""
  set xs $args
  set got_pat 0
  while {[llength $xs]} {
    set a [lindex $xs 0]
    switch -- $a {
      -quiet { set quiet 1; set xs [lrange $xs 1 end] }
      -filter { set xs [lrange $xs 1 end]; set filter [::fc::take xs] }
      default {
        if {[string match -* $a]} {
          ::fc::fail "unknown option '$a' for $cmd (CMD-002)"
        }
        if {!$got_pat} { set patterns [list]; set got_pat 1 }
        lappend patterns {*}[::fc::as_list $a]
        set xs [lrange $xs 1 end]
      }
    }
  }
  variable db
  set matched [list]
  dict for {id obj} [dict get $db lib_objects] {
    if {[dict get $obj object_class] ne $class} continue
    set ok 0
    foreach pat $patterns {
      if {[::fc::hier_match $pat [dict get $obj full_name]] || [::fc::hier_match $pat [dict get $obj name]]} {
        set ok 1
      }
    }
    if {$ok} { lappend matched $id }
  }
  if {$filter ne ""} {
    set matched [::fc::filter_ids $matched $filter]
  }
  set rows [list]
  foreach id $matched {
    lappend rows [list [dict get [dict get $db lib_objects] $id full_name] $id]
  }
  set rows [lsort -dictionary -index 0 $rows]
  set ordered [list]
  foreach row $rows { lappend ordered [lindex $row 1] }
  if {[llength $ordered] == 0 && !$quiet} {
    ::fc::warn_msg SEL-003 "nothing matched for $cmd [join $patterns]"
  }
  return [::fc::new_collection $class $ordered]
}

proc get_cells {args} { ::fc::query_objects cell get_cells {*}$args }
proc get_nets {args} { ::fc::query_objects net get_nets {*}$args }
proc get_pins {args} { ::fc::query_objects pin get_pins {*}$args }
proc get_ports {args} { ::fc::query_objects port get_ports {*}$args }
proc get_clocks {args} { ::fc::query_objects clock get_clocks {*}$args }
proc get_libs {args} { ::fc::query_lib_objects lib get_libs {*}$args }
proc get_lib_cells {args} { ::fc::query_lib_objects lib_cell get_lib_cells {*}$args }

proc all_inputs {args} {
  ::fc::require_linked
  set b [::fc::block_get]
  set ids [list]
  foreach id [::fc::class_ids_in $b port] {
    if {[dict get $b objects $id direction] eq "in"} { lappend ids $id }
  }
  return [::fc::new_collection port $ids]
}

proc all_outputs {args} {
  ::fc::require_linked
  set b [::fc::block_get]
  set ids [list]
  foreach id [::fc::class_ids_in $b port] {
    if {[dict get $b objects $id direction] eq "out"} { lappend ids $id }
  }
  return [::fc::new_collection port $ids]
}

proc all_clocks {args} {
  return [get_clocks]
}

proc all_registers {args} {
  set clock ""
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -clock { set clock [::fc::take xs] }
      default { ::fc::fail "unknown option '$a' for all_registers (SEL-009)" }
    }
  }
  set col [get_cells -hierarchical -quiet -filter "is_sequential == true"]
  if {$clock ne ""} {
    set clocks [get_clocks -quiet $clock]
    if {[sizeof_collection $clocks] == 0} {
      ::fc::warn_msg SEL-003 "no clock named $clock"
      return [::fc::new_collection cell [list]]
    }
  }
  return $col
}

proc get_attribute {args} {
  set quiet 0
  set xs $args
  if {[llength $xs] && [lindex $xs 0] eq "-quiet"} {
    set quiet 1
    set xs [lrange $xs 1 end]
  }
  if {[llength $xs] != 2} {
    ::fc::fail "usage: get_attribute ?-quiet? collection attribute (ATR-001)"
  }
  set ids [::fc::collection_items [lindex $xs 0]]
  set key [lindex $xs 1]
  if {[llength $ids] == 0} {
    if {!$quiet} { ::fc::warn_msg ATR-002 "get_attribute on an empty collection" }
    return ""
  }
  set vals [list]
  foreach id $ids {
    lappend vals [::fc::attr $id $key]
  }
  if {[llength $vals] == 1} { return [lindex $vals 0] }
  return $vals
}

proc set_attribute {args} {
  set quiet 0
  set xs $args
  if {[llength $xs] && [lindex $xs 0] eq "-quiet"} {
    set quiet 1
    set xs [lrange $xs 1 end]
  }
  if {[llength $xs] != 3} {
    ::fc::fail "usage: set_attribute ?-quiet? collection attribute value (ATR-003)"
  }
  set ids [::fc::collection_items [lindex $xs 0]]
  if {[llength $ids] == 0} {
    if {!$quiet} { ::fc::warn_msg ATR-002 "set_attribute on an empty collection" }
    return ""
  }
  foreach id $ids {
    ::fc::set_attr $id [lindex $xs 1] [lindex $xs 2]
  }
  return ""
}

proc remove_attribute {collection attr} {
  foreach id [::fc::collection_items $collection] {
    ::fc::unset_attr $id $attr
  }
  return ""
}

proc list_attributes {collection} {
  set ids [::fc::collection_items $collection]
  if {[llength $ids] == 0} { return [list] }
  set obj [::fc::object_get [lindex $ids 0]]
  set keys [lsort [dict keys $obj]]
  return $keys
}

proc set_dont_touch {objects {value true}} {
  set flag [expr {[string is true -strict $value] ? "true" : "false"}]
  if {![string is boolean -strict $value]} {
    ::fc::fail "set_dont_touch value must be true or false (ATR-004)"
  }
  foreach id [::fc::collection_items $objects] {
    ::fc::set_attr $id dont_touch $flag
  }
  return ""
}

proc get_flow_stage {args} {
  if {![::fc::has_block]} { return none }
  return [dict get [::fc::block_get] stage]
}

foreach {name group summary syntax example} {
  create_lib "Design" "Create a practice library directory" \
    "create_lib -technology tech -ref_libs libs path" \
    "create_lib -technology designs/practice_core/tech.tf -ref_libs designs/practice_core/std.celllib work/practice.ndm"
  open_lib "Design" "Open a saved practice library" "open_lib path" "open_lib work/practice.ndm"
  save_lib "Design" "Write the library and all blocks" "save_lib" "save_lib"
  close_lib "Design" "Close the library" "close_lib ?-force?" "close_lib -force"
  current_lib "Design" "Name of the open library" "current_lib" "current_lib"
  report_lib "Design" "Summarize the open library" "report_lib" "report_lib"
  list_blocks "Design" "List blocks in memory" "list_blocks" "list_blocks"
  create_block "Design" "Create an empty block" "create_block name" "create_block practice_core"
  open_block "Design" "Make a block current, loading it if needed" "open_block name" "open_block practice_core"
  current_block "Design" "Get or set the current block" "current_block ?name?" "current_block"
  save_block "Design" "Write the current block" "save_block" "save_block"
  close_block "Design" "Close the current block" "close_block ?-force?" "close_block -force"
  copy_block "Design" "Copy a block" "copy_block -from a -to b" "copy_block -from practice_core -to practice_core_opt"
  read_verilog "Design" "Read a structural Verilog subset" \
    "read_verilog ?-top name? file" \
    "read_verilog -top practice_core designs/practice_core/practice_core.v"
  link_block "Design" "Elaborate the current block" "link_block" "link_block"
  write_verilog "Design" "Write the Verilog that was read" "write_verilog file" "write_verilog work/out.v"
  read_sdc "Constraints" "Source an SDC subset" "read_sdc file" "read_sdc designs/practice_core/practice_core.sdc"
  write_sdc "Constraints" "Write clocks and a constraint summary" "write_sdc file" "write_sdc work/out.sdc"
  create_clock "Constraints" "Create a clock" \
    "create_clock -name name -period ns ?objects?" \
    "create_clock -name clk -period 2.0 \[get_ports clk\]"
  set_input_delay "Constraints" "Record an input delay" \
    "set_input_delay value -clock clk objects" \
    "set_input_delay 0.3 -clock clk \[all_inputs\]"
  set_output_delay "Constraints" "Record an output delay" \
    "set_output_delay value -clock clk objects" \
    "set_output_delay 0.3 -clock clk \[all_outputs\]"
  set_load "Constraints" "Record a capacitive load" "set_load value objects" "set_load 0.02 \[all_outputs\]"
  set_false_path "Constraints" "Record a false path" \
    "set_false_path ?-from col? ?-to col?" \
    "set_false_path -from \[get_ports rst_n\]"
  set_max_delay "Constraints" "Record a max delay" \
    "set_max_delay value ?-from col? ?-to col?" \
    "set_max_delay 1.5 -from \[all_inputs\] -to \[all_registers\]"
  group_path "Constraints" "Record a path group" \
    "group_path -name name ?-from col? ?-to col?" \
    "group_path -name in2reg -from \[all_inputs\] -to \[all_registers\]"
  create_scenario "Constraints" "Add a scenario" "create_scenario name" "create_scenario test"
  current_scenario "Constraints" "Get or set the current scenario" "current_scenario ?name?" "current_scenario func"
  set_scenario_status "Constraints" "Activate or deactivate a scenario" \
    "set_scenario_status name -active true|false" \
    "set_scenario_status test -active false"
  all_scenarios "Constraints" "Collection of scenarios" "all_scenarios" "all_scenarios"
  create_net "Design" "Create a net, optionally power or ground" \
    "create_net ?-power|-ground? name" "create_net -power VDD"
  connect_pg_net "Design" "Hook pins to a PG net" \
    "connect_pg_net -net name pins" \
    "connect_pg_net -net VDD \[get_pins -hierarchical -filter \"name == VDD\"\]"
  get_cells "Query" "Collection of cells. * does not cross /" \
    "get_cells ?-hierarchical? ?-quiet? ?-filter expr? ?-of_objects col? ?patterns?" \
    "get_cells -hierarchical -filter \"is_sequential == true\""
  get_nets "Query" "Collection of nets" \
    "get_nets ?-hierarchical? ?-filter expr? ?-of_objects col? ?patterns?" \
    "get_nets -of_objects \[get_pins u_alu/y0\]"
  get_pins "Query" "Collection of pins" \
    "get_pins ?-hierarchical? ?-filter expr? ?-of_objects col? ?patterns?" \
    "get_pins -of_objects \[get_cells u_alu\]"
  get_ports "Query" "Collection of ports" \
    "get_ports ?-quiet? ?-filter expr? ?patterns?" "get_ports din_*"
  get_clocks "Query" "Collection of clocks" "get_clocks ?pattern?" "get_clocks clk"
  get_libs "Query" "Collection of reference libraries" "get_libs ?pattern?" "get_libs"
  get_lib_cells "Query" "Collection of library cells" \
    "get_lib_cells ?-filter expr? ?pattern?" "get_lib_cells -filter \"is_sequential == true\""
  all_inputs "Query" "All input ports" "all_inputs" "all_inputs"
  all_outputs "Query" "All output ports" "all_outputs" "all_outputs"
  all_clocks "Query" "All clocks" "all_clocks" "all_clocks"
  all_registers "Query" "Sequential leaf cells" "all_registers ?-clock name?" "all_registers"
  get_attribute "Attributes" "Read an attribute. One object returns a value; many return a list." \
    "get_attribute ?-quiet? collection attribute" \
    "get_attribute \[get_cells u_alu\] ref_name"
  set_attribute "Attributes" "Set an attribute on every object in a collection" \
    "set_attribute collection attribute value" \
    "set_attribute \[all_registers\] practice_tag lab4"
  remove_attribute "Attributes" "Remove an attribute" \
    "remove_attribute collection attribute" \
    "remove_attribute \[get_cells u_alu\] practice_tag"
  list_attributes "Attributes" "Attribute names on the first object" \
    "list_attributes collection" "list_attributes \[get_cells u_alu\]"
  set_dont_touch "Attributes" "Set dont_touch true or false" \
    "set_dont_touch collection ?true|false?" "set_dont_touch \[get_cells u_ctrl\] true"
  get_flow_stage "Flow" "Practice helper: current flow stage name" "get_flow_stage" "get_flow_stage"
} {
  ::fc::register $name $group $summary $syntax $example
}
