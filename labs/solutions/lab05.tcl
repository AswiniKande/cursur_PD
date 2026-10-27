initialize_floorplan -core_utilization 0.65 -side_ratio {1 1} -core_offset {10 10}
place_pins -self
create_placement -floorplan
create_placement_blockage -name keepout -bbox {0 0 5 5}
check_floorplan
