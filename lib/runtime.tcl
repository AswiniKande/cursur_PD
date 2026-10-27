# Session helpers: messages, options, help, redirect, command log.

namespace eval ::fc {
  variable version "practice-1.0"
  variable helpdb [dict create]
  variable appopts [dict create]
  variable hostopts [dict create max_cores 1]
  variable suppressed [list]
  variable capturing 0
  variable capture ""
  variable hist [list]
  variable error_count 0
  variable log_enabled 0
  variable log_path ""
  variable db [dict create current_lib "" current_block "" libs [dict create] blocks [dict create] lib_objects [dict create]]
  variable collections [dict create]
  variable sel_counter 0
}

proc ::fc::fail {msg} {
  return -code error -errorcode FC $msg
}

proc ::fc::register {name group summary syntax example} {
  variable helpdb
  dict set helpdb $name [dict create group $group summary $summary syntax $syntax example $example]
}

proc ::fc::info_msg {id text} {
  variable suppressed
  if {[lsearch -exact $suppressed $id] >= 0} { return }
  puts "Information: $text ($id)"
}

proc ::fc::warn_msg {id text} {
  variable suppressed
  if {[lsearch -exact $suppressed $id] >= 0} { return }
  puts stderr "Warning: $text ($id)"
}

proc ::fc::print_error {result opts} {
  puts stderr "Error: $result"
  set ec ""
  catch { set ec [dict get $opts -errorcode] }
  if {$ec ne "FC"} {
    set info ""
    catch { set info [dict get $opts -errorinfo] }
    if {$info ne ""} {
      puts stderr $info
    }
  }
}

proc ::fc::log_cmd {script} {
  variable log_enabled
  variable log_path
  if {!$log_enabled || $log_path eq ""} { return }
  set fh [open $log_path a]
  puts $fh $script
  close $fh
}

proc ::fc::init_options {} {
  variable appopts
  dict set appopts shell.common.collection_result_display_limit 100
  dict set appopts shell.common.report_default_significant_digits 3
  dict set appopts place.coarse.max_density 0.75
  dict set appopts place.coarse.continue_on_missing_scandef false
  dict set appopts opt.common.max_fanout 40
  dict set appopts time.delay_calculation_style auto
  dict set appopts compile.seqmap.identify_shift_registers false
}

proc ::fc::app_get {name} {
  variable appopts
  if {![dict exists $appopts $name]} {
    ::fc::fail "unknown app option '$name' (APP-001)"
  }
  return [dict get $appopts $name]
}

proc ::fc::format_result {result} {
  if {[::fc::is_collection $result]} {
    set names [::fc::collection_names $result]
    set n [llength $names]
    if {$n == 0} { return "" }
    set limit [::fc::app_get shell.common.collection_result_display_limit]
    if {![string is integer -strict $limit] || $limit <= 0} {
      return [join $names]
    }
    if {$n > $limit} {
      set shown [lrange $names 0 [expr {$limit - 1}]]
      return "[join $shown]\n... ($n objects total)"
    }
    return [join $names]
  }
  return $result
}

proc ::fc::eval_script {script mode} {
  variable error_count
  ::fc::log_cmd $script
  set code [catch {uplevel #0 $script} result opts]
  if {$code} {
    incr error_count
    ::fc::print_error $result $opts
    if {$mode eq "interactive"} {
      return ""
    }
    return -code error $result
  }
  if {$mode eq "interactive" || $mode eq "show"} {
    set shown [::fc::format_result $result]
    if {$shown ne ""} {
      puts $shown
    }
  }
  return $result
}

# Capture stdout while redirect is active. File channels still write through.
if {[info commands ::fc::puts_orig] eq ""} {
  rename ::puts ::fc::puts_orig
  proc ::puts {args} {
    if {!$::fc::capturing} {
      ::fc::puts_orig {*}$args
      return
    }
    set nonewline 0
    set xs $args
    if {[llength $xs] == 0} {
      ::fc::fail "puts called with no arguments"
    }
    if {[lindex $xs 0] eq "-nonewline"} {
      set nonewline 1
      set xs [lrange $xs 1 end]
    }
    if {[llength $xs] == 1} {
      append ::fc::capture [lindex $xs 0]
      if {!$nonewline} { append ::fc::capture "\n" }
      return
    }
    if {[llength $xs] == 2} {
      set ch [lindex $xs 0]
      set str [lindex $xs 1]
      if {$ch eq "stdout"} {
        append ::fc::capture $str
        if {!$nonewline} { append ::fc::capture "\n" }
        return
      }
      if {$nonewline} {
        ::fc::puts_orig -nonewline $ch $str
      } else {
        ::fc::puts_orig $ch $str
      }
      return
    }
    ::fc::puts_orig {*}$args
  }
}

proc ::fc::take {xsVar} {
  upvar 1 $xsVar xs
  if {[llength $xs] == 0} {
    ::fc::fail "missing argument (CMD-003)"
  }
  set v [lindex $xs 0]
  set xs [lrange $xs 1 end]
  return $v
}

proc ::fc::as_list {value} {
  # A single pattern stays one pattern even if it contains no spaces.
  # A Tcl list of patterns is already a list when the caller passed {a b}.
  if {[llength $value] > 1} {
    return $value
  }
  return [list $value]
}

proc echo {args} {
  puts [join $args]
  return ""
}

proc printvar {args} {
  if {[llength $args] == 0} {
    ::fc::fail "usage: printvar var ?var ...? (CMD-004)"
  }
  foreach v $args {
    if {![info exists ::$v]} {
      ::fc::warn_msg VAR-001 "variable '$v' is not set"
      continue
    }
    puts "$v = [set ::$v]"
  }
  return ""
}

proc alias {args} {
  if {[llength $args] == 0} {
    foreach name [lsort [interp aliases]] {
      puts "alias $name [interp alias {} $name]"
    }
    return ""
  }
  if {[llength $args] == 1} {
    return [interp alias {} [lindex $args 0]]
  }
  set name [lindex $args 0]
  interp alias {} $name {} {*}[lrange $args 1 end]
  return ""
}

proc which {cmd} {
  set hits [info commands $cmd]
  if {$hits eq ""} {
    ::fc::fail "command '$cmd' not found (CMD-005)"
  }
  puts $cmd
  return $cmd
}

proc sh {args} {
  if {[llength $args] == 0} {
    ::fc::fail "usage: sh command ?arg ...? (CMD-006)"
  }
  set out [exec {*}$args]
  if {$out ne ""} {
    puts $out
  }
  return ""
}

proc quit {{code 0}} {
  exit $code
}

proc suppress_message {args} {
  variable ::fc::suppressed
  if {[llength $args] == 0} {
    ::fc::fail "usage: suppress_message id ?id ...? (MSG-001)"
  }
  foreach id $args {
    if {[lsearch -exact $suppressed $id] < 0} {
      lappend suppressed $id
    }
  }
  return ""
}

proc unsuppress_message {args} {
  variable ::fc::suppressed
  if {[llength $args] == 0} {
    set suppressed [list]
    return ""
  }
  foreach id $args {
    set i [lsearch -exact $suppressed $id]
    if {$i >= 0} {
      set suppressed [lreplace $suppressed $i $i]
    }
  }
  return ""
}

proc set_message_info {args} {
  set id ""
  set limit ""
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -id { set id [::fc::take xs] }
      -limit { set limit [::fc::take xs] }
      default { ::fc::fail "unknown option '$a' for set_message_info (MSG-002)" }
    }
  }
  if {$id eq "" || $limit eq ""} {
    ::fc::fail "usage: set_message_info -id ID -limit N (MSG-002)"
  }
  if {$limit == 0} {
    suppress_message $id
  } else {
    unsuppress_message $id
  }
  return ""
}

proc redirect {args} {
  set mode w
  set file ""
  set rest [list]
  set xs $args
  while {[llength $xs]} {
    set a [lindex $xs 0]
    switch -- $a {
      -append {
        set mode a
        set xs [lrange $xs 1 end]
      }
      -file {
        set xs [lrange $xs 1 end]
        set file [::fc::take xs]
      }
      default {
        lappend rest $a
        set xs [lrange $xs 1 end]
      }
    }
  }
  if {$file eq ""} {
    if {[llength $rest] != 2} {
      ::fc::fail "usage: redirect ?-append? ?-file file? file script (CMD-007)"
    }
    set file [lindex $rest 0]
    set script [lindex $rest 1]
  } else {
    if {[llength $rest] != 1} {
      ::fc::fail "usage: redirect ?-append? -file file script (CMD-007)"
    }
    set script [lindex $rest 0]
  }
  set dir [file dirname $file]
  if {$dir ne "." && ![file isdirectory $dir]} {
    file mkdir $dir
  }
  set saved_flag $::fc::capturing
  set saved_buf $::fc::capture
  set ::fc::capturing 1
  set ::fc::capture ""
  set code [catch {uplevel 1 $script} result opts]
  set data $::fc::capture
  set ::fc::capture $saved_buf
  set ::fc::capturing $saved_flag
  set fh [open $file $mode]
  puts -nonewline $fh $data
  close $fh
  if {$code} {
    return -options $opts $result
  }
  return ""
}

proc set_app_options {args} {
  variable ::fc::appopts
  set name ""
  set value ""
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -name { set name [::fc::take xs] }
      -value { set value [::fc::take xs] }
      -list {
        set pairs [::fc::take xs]
        if {[llength $pairs] % 2 != 0} {
          ::fc::fail "-list expects name value pairs (APP-002)"
        }
        foreach {n v} $pairs {
          dict set appopts $n $v
        }
      }
      default { ::fc::fail "unknown option '$a' for set_app_options (APP-002)" }
    }
  }
  if {$name ne ""} {
    dict set appopts $name $value
  }
  return ""
}

proc get_app_option {args} {
  # Real shells differ on singular vs plural; accept the name students type.
  set name ""
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -name { set name [::fc::take xs] }
      default { ::fc::fail "unknown option '$a' for get_app_option (APP-003)" }
    }
  }
  if {$name eq ""} {
    ::fc::fail "usage: get_app_option -name option (APP-003)"
  }
  return [::fc::app_get $name]
}
# Common plural spelling.
interp alias {} get_app_options {} get_app_option

proc report_app_options {args} {
  variable ::fc::appopts
  set pat "*"
  if {[llength $args] > 0} {
    set pat [lindex $args 0]
  }
  puts [format "%-52s %s" "Option" "Value"]
  puts [string repeat "-" 72]
  foreach name [lsort [dict keys $appopts]] {
    if {[string match $pat $name]} {
      puts [format "%-52s %s" $name [dict get $appopts $name]]
    }
  }
  return ""
}

proc set_host_options {args} {
  variable ::fc::hostopts
  set xs $args
  while {[llength $xs]} {
    set a [::fc::take xs]
    switch -- $a {
      -max_cores {
        set n [::fc::take xs]
        if {![string is integer -strict $n] || $n < 1} {
          ::fc::fail "-max_cores expects a positive integer (HOST-001)"
        }
        dict set hostopts max_cores $n
      }
      default { ::fc::fail "unknown option '$a' for set_host_options (HOST-001)" }
    }
  }
  return ""
}

proc report_host_options {args} {
  variable ::fc::hostopts
  puts "Host options"
  puts [format "  max_cores  %s" [dict get $hostopts max_cores]]
  return ""
}
interp alias {} get_host_options {} report_host_options

proc help {args} {
  variable ::fc::helpdb
  if {[llength $args] == 0} {
    puts "Commands (educational fc_shell subset). Try: man <command>   apropos <word>"
    puts ""
    set groups [list]
    dict for {name info} $helpdb {
      set g [dict get $info group]
      if {[lsearch -exact $groups $g] < 0} { lappend groups $g }
    }
    foreach g $groups {
      puts $g
      dict for {name info} $helpdb {
        if {[dict get $info group] eq $g} {
          puts [format "  %-28s %s" $name [dict get $info summary]]
        }
      }
      puts ""
    }
    return ""
  }
  set name [lindex $args 0]
  if {![dict exists $helpdb $name]} {
    ::fc::fail "no help for '$name'. Try apropos. (CMD-008)"
  }
  set info [dict get $helpdb $name]
  puts "NAME"
  puts "  $name — [dict get $info summary]"
  puts ""
  puts "SYNTAX"
  puts "  [dict get $info syntax]"
  set ex [dict get $info example]
  if {$ex ne ""} {
    puts ""
    puts "EXAMPLE"
    foreach line [split $ex \n] {
      puts "  $line"
    }
  }
  return ""
}
interp alias {} man {} help

proc apropos {pat} {
  variable ::fc::helpdb
  set n 0
  foreach name [lsort [dict keys $helpdb]] {
    set info [dict get $helpdb $name]
    set summary [dict get $info summary]
    if {[string match -nocase "*$pat*" $name] || [string match -nocase "*$pat*" $summary]} {
      puts [format "%-28s %s" $name $summary]
      incr n
    }
  }
  if {$n == 0} {
    puts "no topics match '$pat'"
  }
  return ""
}

proc history {args} {
  variable ::fc::hist
  set i 1
  foreach h $::fc::hist {
    puts [format "%4d  %s" $i [string map {\n " \\ "} $h]]
    incr i
  }
  return ""
}

proc report_platform {args} {
  puts "fc_shell practice platform $::fc::version"
  puts "Educational simulator for Fusion Compiler Tcl scripting."
  puts "This is not Synopsys software and does not check out a license."
  puts "Root: $::fc::root"
  return ""
}

proc start_gui {args} {
  ::fc::info_msg GUI-001 "no GUI in the practice platform; reports print in this terminal"
  return ""
}

::fc::init_options

::fc::register help "Shell" "List commands, or show one command" \
  "help ?command?" "help get_cells"
::fc::register man "Shell" "Same as help" "man command" "man sizeof_collection"
::fc::register apropos "Shell" "Search command names and summaries" \
  "apropos word" "apropos collection"
::fc::register echo "Shell" "Print a line" "echo ?arg ...?" {echo "hello [current_block]"}
::fc::register printvar "Shell" "Print global variables" "printvar var ?var ...?" "printvar design_name"
::fc::register alias "Shell" "Define a command alias" "alias ?name? ?body ...?" "alias rq report_qor"
::fc::register which "Shell" "Show whether a command exists" "which command" "which link_block"
::fc::register history "Shell" "Show commands entered in this session" "history" "history"
::fc::register redirect "Shell" "Send stdout of a script into a file" \
  "redirect ?-append? ?-file? file script" "redirect -file reports/qor.rpt { report_qor }"
::fc::register suppress_message "Shell" "Hide messages with an id" \
  "suppress_message id ?id ...?" "suppress_message SEL-003"
::fc::register unsuppress_message "Shell" "Show messages again" \
  "unsuppress_message ?id ...?" "unsuppress_message SEL-003"
::fc::register set_message_info "Shell" "Limit a message id (0 suppresses it)" \
  "set_message_info -id ID -limit N" "set_message_info -id SEL-003 -limit 0"
::fc::register set_app_options "Shell" "Set a shell option (unknown names are stored too)" \
  "set_app_options -name name -value value" "set_app_options -name place.coarse.max_density -value 0.8"
::fc::register get_app_option "Shell" "Read a shell option" \
  "get_app_option -name name" "get_app_option -name opt.common.max_fanout"
::fc::register get_app_options "Shell" "Alias of get_app_option" \
  "get_app_options -name name" "get_app_options -name opt.common.max_fanout"
::fc::register report_app_options "Shell" "List app options" \
  "report_app_options ?pattern?" "report_app_options place.*"
::fc::register set_host_options "Shell" "Set host core count" \
  "set_host_options -max_cores N" "set_host_options -max_cores 4"
::fc::register report_host_options "Shell" "Show host options" "report_host_options" "report_host_options"
::fc::register get_host_options "Shell" "Alias of report_host_options" "get_host_options" "get_host_options"
::fc::register sh "Shell" "Run a host command" "sh command ?arg ...?" "sh date"
::fc::register quit "Shell" "Leave the shell" "quit ?code?" "quit"
::fc::register report_platform "Shell" "Show practice-platform version" "report_platform" "report_platform"
::fc::register start_gui "Shell" "Explain that this platform is terminal only" "start_gui" "start_gui"
