# fc_shell practice platform

A local Tcl shell for practicing the commands used in Synopsys Fusion Compiler. It reads a small hierarchical netlist, builds collections, and walks a floorplan-to-route flow whose timing numbers are estimated and stable.

This is not Synopsys software. It does not check out a license, and it does not implement a real timer, placer, or router.

## Run it

```bash
./bin/fc_shell
```

If `rlwrap` is installed, the interactive prompt keeps history and completes command names. Leave with `quit`.

Batch mode:

```bash
./bin/fc_shell -f examples/proto_flow.tcl
./bin/fc_shell -no_log -x "practice_labs"
```

`make test` runs the regression suite. `make shell` opens the prompt.

## First session

```tcl
practice_labs
practice_start 1
practice_cheatsheet
practice_demo
```

Labs 1 through 6 cover Tcl variables, building a block, collections, attributes, floorplanning, and a `place_opt` procedure. `practice_check` grades the lab you started. `practice_hint` and `practice_solution` are there when you want them.

The design kit is `designs/practice_core/`:

| File | Role |
| --- | --- |
| `practice_core.v` | Structural netlist (`practice_core`, `alu4`, `regbit`, `decoder`, `control`) |
| `practice_core.sdc` | One 2.0 ns clock and a few delays |
| `std.celllib` | Practice cell library (not Liberty) |
| `tech.tf` | Practice technology (not a Synopsys `.tf`) |

A normal build looks like this:

```tcl
set root $::fc::root
create_lib -technology $root/designs/practice_core/tech.tf \
           -ref_libs $root/designs/practice_core/std.celllib \
           work/practice.ndm
read_verilog -top practice_core $root/designs/practice_core/practice_core.v
link_block
read_sdc $root/designs/practice_core/practice_core.sdc
initialize_floorplan -core_utilization 0.65 -side_ratio {1 1} -core_offset {10 10}
place_pins -self
create_placement -floorplan
place_opt
clock_opt
route_auto
route_opt
report_qor
save_block
save_lib
```

`compile_fusion` runs whatever is left of that sequence after the floorplan exists.

## Collections

Query commands return collection ids (`_sel1`), same idea as the real shell. Pass those ids around. Use `get_object_name` when you want an ordinary Tcl list.

`*` and `?` do not cross `/`.

```tcl
get_cells *                                          ;# top level only
get_cells u_rf*/*                                    ;# one level down
get_cells -hierarchical -filter "is_sequential == true"
get_pins -hierarchical -filter "name == CK"
sizeof_collection [all_registers]
foreach_in_collection c [all_registers] {
  echo "[get_object_name $c] [get_attribute $c ref_name]"
}
```

The loop variable is a one-object collection. Filters accept `== != > < >= <= =~ !~`, joined with `&&`, `||`, and parentheses. `=~` uses ordinary Tcl glob, so `*` can cross `/` there.

## What the flow is pretending

Each stage has a fixed estimated WNS so you can practice reports without a timer:

| Stage | WNS (ns) |
| --- | --- |
| linked | -0.450 |
| floorplanned | -0.300 |
| placed | -0.180 |
| place_opt | -0.060 |
| clock_opt | 0.010 |
| routed | -0.030 |
| route_opt | 0.040 |

Leaf cells also get deterministic origins at `create_placement`. Library area is in µm². Every leaf has implicit `VDD` and `VSS` pins for `connect_pg_net`.

Commands that are out of scope print `unknown command` rather than silently doing something else. `help`, `man`, and `apropos` list the subset that is implemented. `report_platform` prints the version.
