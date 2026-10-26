set_dont_touch [get_cells u_ctrl] true
foreach_in_collection r [all_registers] {
  set_attribute $r practice_tag lab4
}
redirect -file reports/qor_lab4.rpt { report_qor }
