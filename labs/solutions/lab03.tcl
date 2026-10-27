set nleaves [sizeof_collection [get_cells -hierarchical -filter "is_hierarchical == false"]]
set seq_names [lsort [get_object_name [all_registers]]]
set rf_cells [lsort [get_object_name [get_cells u_rf*/*]]]
set clk_pins [sizeof_collection [get_pins -hierarchical -filter "name == CK"]]
