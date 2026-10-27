# Practice constraints for practice_core. Period is in ns.
create_clock -name clk -period 2.0 [get_ports clk]
set_input_delay 0.30 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 0.30 -clock clk [all_outputs]
set_false_path -from [get_ports rst_n]
set_load 0.02 [all_outputs]
