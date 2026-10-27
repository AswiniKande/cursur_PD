# fc_shell practice platform entry point.
namespace eval ::fc {}
set ::fc::root [file normalize [file join [file dirname [info script]] ..]]

source [file join $::fc::root lib runtime.tcl]
source [file join $::fc::root lib collection.tcl]
source [file join $::fc::root lib design.tcl]
source [file join $::fc::root lib flow.tcl]
source [file join $::fc::root lib reports.tcl]
source [file join $::fc::root lib labs.tcl]

# `package require` (used by `clock format`) calls ::tcl::tm::UnknownHandler,
# which Tcl normally autoloads. Load it now so the shell's unknown handler
# does not swallow that lookup. Other library commands still autoload.
catch {source [file join $::tcl_library tm.tcl]}

proc unknown {args} {
  set cmd [lindex $args 0]
  if {![info exists ::auto_noload] && ![info exists ::fc::unknown_pending($cmd)]} {
    set ::fc::unknown_pending($cmd) 1
    set loaded 0
    catch {set loaded [auto_load $cmd]}
    set ready [expr {$loaded || [namespace which -command $cmd] ne ""}]
    if {$ready} {
      set code [catch {uplevel 1 $args} result opts]
      unset ::fc::unknown_pending($cmd)
      return -options $opts $result
    }
    unset ::fc::unknown_pending($cmd)
  }
  ::fc::fail "unknown command '$cmd' (CMD-001). Try 'help' or 'apropos $cmd'."
}

proc ::fc::stdin_is_tty {} {
  if {[info exists ::env(FC_SHELL_FORCE_INTERACTIVE)] && $::env(FC_SHELL_FORCE_INTERACTIVE) ne "0"} {
    return 1
  }
  if {[catch {exec /usr/bin/test -t 0 <@stdin}]} {
    return 0
  }
  return 1
}

proc ::fc::banner {} {
  puts "============================================================"
  puts " fc_shell practice platform  ($::fc::version)"
  puts " Educational simulator for Fusion Compiler Tcl scripting."
  puts " This is not Synopsys software and does not use a license."
  puts "============================================================"
  puts "Design kit : [file join $::fc::root designs practice_core]"
  puts "Start here : practice_labs"
  puts "Help       : help | man <command> | apropos <word>"
  puts "============================================================"
}

proc ::fc::history_add {script} {
  variable hist
  lappend hist $script
}

proc ::fc::history_get {spec} {
  variable hist
  if {[llength $hist] == 0} {
    ::fc::fail "history is empty (CMD-009)"
  }
  if {$spec eq "!" || $spec eq "-1"} {
    return [lindex $hist end]
  }
  if {![string is integer -strict $spec]} {
    ::fc::fail "bad history reference '!$spec' (CMD-009)"
  }
  set n $spec
  if {$n < 0} {
    set n [expr {[llength $hist] + $n + 1}]
  }
  if {$n < 1 || $n > [llength $hist]} {
    ::fc::fail "history event !$spec does not exist (CMD-009)"
  }
  return [lindex $hist [expr {$n - 1}]]
}

proc ::fc::repl {} {
  variable hist
  ::fc::banner
  set buf ""
  while {1} {
    if {$buf eq ""} {
      puts -nonewline "fc_shell> "
    } else {
      puts -nonewline "fc_shell? "
    }
    flush stdout
    if {[gets stdin line] < 0} { break }
    if {$buf eq "" && [regexp {^!(\S+)$} [string trim $line] -> spec]} {
      set line [::fc::history_get $spec]
      puts $line
    }
    if {$buf eq ""} {
      set buf $line
    } else {
      append buf "\n" $line
    }
    if {![info complete $buf]} { continue }
    set script $buf
    set buf ""
    if {[string trim $script] eq ""} { continue }
    ::fc::history_add $script
    ::fc::eval_script $script interactive
  }
  puts ""
}

proc ::fc::usage {} {
  puts "Usage: fc_shell \[-no_log\] \[-output_log_file file\] \[-f file\] \[-x script\]"
  puts "       fc_shell -version"
  puts "Interactive when stdin is a terminal. Piped stdin is read as a script."
}

proc ::fc::main {argv} {
  variable log_enabled
  variable log_path
  set log_enabled 1
  set log_path "fc_shell_command.log"
  set files [list]
  set cmds [list]
  set i 0
  while {$i < [llength $argv]} {
    set a [lindex $argv $i]
    switch -- $a {
      -no_log { set log_enabled 0 }
      -output_log_file {
        incr i
        set log_path [lindex $argv $i]
      }
      -f {
        incr i
        lappend files [lindex $argv $i]
      }
      -x {
        incr i
        lappend cmds [lindex $argv $i]
      }
      -version {
        puts "fc_shell practice platform $::fc::version"
        return 0
      }
      -h - -help {
        ::fc::usage
        return 0
      }
      default {
        puts stderr "Error: unknown argument '$a' (CMD-000)"
        ::fc::usage
        exit 1
      }
    }
    incr i
  }
  if {$log_enabled} {
    set fh [open $log_path a]
    puts $fh "# fc_shell practice [clock format [clock seconds] -gmt 1]"
    close $fh
  }
  set batch [expr {[llength $files] > 0 || [llength $cmds] > 0}]
  if {!$batch && ![::fc::stdin_is_tty]} {
    set script [read stdin]
    if {[string trim $script] ne ""} {
      if {[catch {::fc::eval_script $script batch}]} {
        exit 1
      }
    }
    return 0
  }
  foreach f $files {
    if {![file exists $f]} {
      ::fc::fail "script not found: $f (IO-001)"
    }
    set fh [open $f r]
    set script [read $fh]
    close $fh
    if {[catch {::fc::eval_script $script batch}]} {
      exit 1
    }
  }
  foreach c $cmds {
    if {[catch {::fc::eval_script $c show}]} {
      exit 1
    }
  }
  if {!$batch} {
    ::fc::repl
  }
  return 0
}

if {[info exists ::fc::library_only] && $::fc::library_only} {
  return
}

if {[catch {::fc::main $argv} err opts]} {
  set ec ""
  catch { set ec [dict get $opts -errorcode] }
  if {$ec eq "FC"} {
    puts stderr "Error: $err"
  } else {
    ::fc::print_error $err $opts
  }
  exit 1
}
exit 0
