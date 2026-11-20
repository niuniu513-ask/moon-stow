///|
/// Determinism matters: a plan that changes between runs cannot be audited or
/// replayed on the dock, so the same input must always produce the same layout.
test "pack: same input gives the same layout" {
  let cargos = [
    Cargo::new("A", Dimensions::new(1200, 1000, 800), 20_000),
    Cargo::new("B", Dimensions::new(800, 600, 600), 9_000),
    Cargo::new("C", Dimensions::new(600, 400, 400), 4_000),
    Cargo::new("D", Dimensions::new(1000, 800, 700), 15_000),
  ]
  let unit = LoadUnit::container_20ft("CONT1")
  let first = pack(unit, cargos, StowRules::default())
  let second = pack(unit, cargos, StowRules::default())
  assert_eq(first.placements.length(), second.placements.length())
  for i in 0..<first.placements.length() {
    let a = first.placements[i]
    let b = second.placements[i]
    assert_true(a.cargo_id == b.cargo_id)
    assert_true(a.box.min == b.box.min)
    assert_true(a.box.size == b.box.size)
    assert_true(a.orientation == b.orientation)
  }
}

///|
test "pack: payload limit stops the packer" {
  let unit = LoadUnit::pallet_eur("P").with_payload(5_000)
  let cargos = [
    Cargo::new("H1", Dimensions::new(400, 400, 400), 3_000),
    Cargo::new("H2", Dimensions::new(400, 400, 400), 3_000),
    Cargo::new("H3", Dimensions::new(400, 400, 400), 3_000),
  ]
  let plan = pack(unit, cargos, StowRules::default())
  assert_eq(plan.placements.length(), 1)
  assert_eq(plan.unplaced.length(), 2)
  assert_true(plan.metrics.total_weight_g <= 5_000)
}

///|
test "pack: stack layers are respected" {
  let unit = LoadUnit::pallet_eur("P")
  let cargos = [
    Cargo::new("LOW", Dimensions::new(400, 400, 300), 5_000),
    Cargo::new("TOP", Dimensions::new(400, 400, 300), 5_000).with_stack_limit(
      1, 60_000,
    ),
  ]
  let rules = StowRules::default().with_layer_cap(1)
  let plan = pack(unit, cargos, rules)
  assert_eq(plan.placements.length(), 2)
  // both on the floor, because a second layer is forbidden
  assert_eq(plan.metrics.stack_height_mm, 300)
  assert_true(is_clear(plan.violations))
}

///|
test "pack: nothing is stacked on a fragile item" {
  let unit = LoadUnit::container_20ft("C")
  let cargos = [
    Cargo::new("GLASS", Dimensions::new(600, 400, 400), 2_000).fragile_item(),
    Cargo::new("HEAVY", Dimensions::new(600, 400, 400), 20_000),
  ]
  let plan = pack(unit, cargos, StowRules::default())
  assert_eq(plan.placements.length(), 2)
  for i in 0..<plan.placements.length() {
    if plan.placements[i].cargo_id == "GLASS" {
      assert_eq(load_on(plan.placements, cargos, i), 0)
    }
  }
}

///|
test "pack: unreviewed dangerous goods block the entire manifest" {
  let unit = LoadUnit::container_20ft("C")
  let cargos = [
    Cargo::new("EXPL", Dimensions::new(800, 600, 600), 10_000).with_hazard(
      Hazard::new(Explosive, "0004", II),
    ),
    Cargo::new("OXI", Dimensions::new(800, 600, 600), 10_000).with_hazard(
      Hazard::new(Oxidizer, "1479", II),
    ),
  ]
  let plan = pack(unit, cargos, StowRules::default())
  assert_eq(plan.placements.length(), 0)
  assert_eq(plan.unplaced.length(), 2)
  assert_false(is_clear(plan.violations))
}

///|
test "pack: an item that is too big is reported, not placed" {
  let unit = LoadUnit::pallet_eur("P")
  let cargos = [Cargo::new("HUGE", Dimensions::new(2_000, 2_000, 2_000), 5_000)]
  let plan = pack(unit, cargos, StowRules::default())
  assert_eq(plan.placements.length(), 0)
  assert_eq(plan.unplaced.length(), 1)
  let verdict = pack_all(unit, cargos, StowRules::default())
  assert_true(verdict is None)
}

///|
test "verify: a multi-stop plan loaded in the wrong order is flagged" {
  let unit = LoadUnit::container_20ft("C")
  let cargos = [
    Cargo::new("DOOR", Dimensions::new(1000, 1000, 1000), 8_000).with_stop(0),
    Cargo::new("BACK", Dimensions::new(1000, 1000, 1000), 8_000).with_stop(1),
  ]
  // deliberately load the far stop at the door
  let placements : Array[Placement] = [
    {
      cargo_id: "BACK",
      cargo_index: 1,
      orientation: LWH,
      box: Aabb::at(0, 0, 0, Dimensions::new(1000, 1000, 1000)),
      stop: 1,
      layer: 1,
    },
    {
      cargo_id: "DOOR",
      cargo_index: 0,
      orientation: LWH,
      box: Aabb::at(2000, 0, 0, Dimensions::new(1000, 1000, 1000)),
      stop: 0,
      layer: 1,
    },
  ]
  let violations = verify(unit, cargos, placements, StowRules::default())
  assert_true(!is_clear(violations))
  assert_true(count_by_severity(violations, Error) > 0)
}
