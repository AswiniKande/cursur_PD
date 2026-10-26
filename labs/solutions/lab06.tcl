proc implement_proto {} {
  initialize_floorplan -core_utilization 0.60 -side_ratio {1 1} -core_offset {8 8}
  place_pins -self
  create_placement -floorplan
  place_opt
  save_block
}
