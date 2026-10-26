set design_name practice_core
set target_util 0.7
set mods {alu4 regbit decoder control}

proc banner {} {
  return "$::design_name util=[format %.2f $::target_util]"
}
