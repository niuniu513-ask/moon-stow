///|
fn audit_placement(
  cargos : Array[Cargo],
  index : Int32,
  x : Int32,
  z : Int32,
  layer : Int32,
) -> Placement {
  {
    cargo_id: cargos[index].id,
    cargo_index: index,
    orientation: LWH,
    box: Aabb::at(x, 0, z, cargos[index].dims),
    stop: cargos[index].stop,
    layer,
  }
}

///|
test "audit: load propagates through the entire stack and to the floor" {
  let cargos = [
    Cargo::new("BASE", Dimensions::new(600, 400, 400), 20_000).with_stack_limit(
      3, 15_000,
    ),
    Cargo::new("MID", Dimensions::new(600, 400, 400), 10_000),
    Cargo::new("TOP", Dimensions::new(600, 400, 400), 10_000),
  ]
  let placements = [
    audit_placement(cargos, 0, 0, 0, 1),
    audit_placement(cargos, 1, 0, 400, 2),
    audit_placement(cargos, 2, 0, 800, 3),
  ]
  assert_eq(load_on(placements, cargos, 0), 20_000)
  assert_eq(max_floor_pressure(placements, cargos), 166_666)
  let unit = {
    ..LoadUnit::pallet_eur("P"),
    dims: Dimensions::new(600, 400, 1800),
    floor_limit_g_per_m2: 0,
  }
  assert_true(
    has_hazard_kind(
      verify(unit, cargos, placements, StowRules::default()),
      TopLoadExceeded,
    ),
  )
  assert_eq(
    pack_ordered(unit, cargos, StowRules::default(), [0, 1, 2]).placements.length(),
    2,
  )
}

///|
test "audit: axle moments do not overflow at normal truck weights" {
  let cargos = [
    Cargo::new("HEAVY", Dimensions::new(1000, 1000, 1000), 10_000_000),
  ]
  let placements = [audit_placement(cargos, 0, 4500, 0, 1)]
  let unit = {
    ..LoadUnit::truck_rigid("T"),
    tare_g: 0,
    axles: [Axle::new(0, 20_000_000), Axle::new(10_000, 20_000_000)],
  }
  let loads = axle_loads(unit, placements, cargos)
  assert_eq(loads[0], 5_000_000)
  assert_eq(loads[1], 5_000_000)
}

///|
test "audit: carton picks refer to original goods indices" {
  let goods = [
    Cargo::new("SMALL", Dimensions::new(100, 100, 100), 1000),
    Cargo::new("LARGE", Dimensions::new(200, 200, 200), 2000),
  ]
  let result = cartonize(
    [CartonSpec::new("BOX", Dimensions::new(200, 200, 200), 3000, 100)],
    goods,
    StowRules::default(),
  )
  assert_eq(result.picks.length(), 2)
  for pick in result.picks {
    for p in pick.plan.placements {
      assert_eq(p.cargo_id, goods[p.cargo_index].id)
    }
  }
}

///|
test "audit: oversized goods do not prevent cartonizing smaller goods" {
  let goods = [
    Cargo::new("HUGE", Dimensions::new(1000, 1000, 1000), 1000),
    Cargo::new("SMALL", Dimensions::new(100, 100, 100), 1000),
  ]
  let result = cartonize(
    [CartonSpec::new("BOX", Dimensions::new(200, 200, 200), 3000, 100)],
    goods,
    StowRules::default(),
  )
  assert_eq(result.picks.length(), 1)
  assert_eq(result.unpacked.length(), 1)
  assert_eq(result.unpacked[0].cargo_id, "HUGE")
}

///|
test "audit: declared item gaps are checked and generated" {
  let cargos = [
    Cargo::new("A", Dimensions::new(400, 400, 400), 1000).with_gap(100),
    Cargo::new("B", Dimensions::new(400, 400, 400), 1000),
  ]
  let unit = LoadUnit::container_20ft("C")
  let touching = [
    audit_placement(cargos, 0, 0, 0, 1),
    audit_placement(cargos, 1, 400, 0, 1),
  ]
  assert_false(is_clear(verify(unit, cargos, touching, StowRules::default())))
  let plan = pack(unit, cargos, StowRules::default())
  assert_eq(plan.placements.length(), 2)
  assert_true(plan.placements[0].box.gap(plan.placements[1].box) >= 100)
}

///|
test "audit: declared clearance is lateral and never forbids stacking" {
  let cargos = [
    Cargo::new("BASE", Dimensions::new(400, 400, 400), 20_000)
    .with_gap(100)
    .with_stack_limit(3, 500_000),
    Cargo::new("TOP", Dimensions::new(400, 400, 400), 10_000).with_gap(100),
  ]
  let unit = LoadUnit::container_20ft("C")
  let stacked = [
    audit_placement(cargos, 0, 0, 0, 1),
    audit_placement(cargos, 1, 0, 400, 2),
  ]
  let findings = verify(unit, cargos, stacked, StowRules::default())
  assert_false(has_hazard_kind(findings, CargoGap))
  assert_true(is_clear(findings))
  // The same two pieces side by side share a height band, so the declared
  // 100 mm lateral clearance applies and touching is rejected.
  let touching = [
    audit_placement(cargos, 0, 0, 0, 1),
    audit_placement(cargos, 1, 400, 0, 1),
  ]
  assert_true(
    has_hazard_kind(
      verify(unit, cargos, touching, StowRules::default()),
      CargoGap,
    ),
  )
  // Moving it clear of the declaration is accepted again.
  let clear = [
    audit_placement(cargos, 0, 0, 0, 1),
    audit_placement(cargos, 1, 500, 0, 1),
  ]
  assert_false(
    has_hazard_kind(verify(unit, cargos, clear, StowRules::default()), CargoGap),
  )
}

///|
test "audit: reverse door and forged stop metadata cannot bypass unloading checks" {
  let cargos = [
    Cargo::new("EARLY", Dimensions::new(400, 400, 400), 1000).with_stop(0),
    Cargo::new("LATE", Dimensions::new(400, 400, 400), 1000).with_stop(1),
  ]
  let placements = [
    audit_placement(cargos, 0, 0, 0, 1),
    audit_placement(cargos, 1, 600, 0, 1),
  ]
  let unit = { ..LoadUnit::container_20ft("C"), rear_door_at_origin: false, }
  assert_true(
    has_hazard_kind(
      verify(unit, cargos, placements, StowRules::default()),
      Overstow,
    ),
  )
  let forged = [placements[0], { ..placements[1], stop: 0, }]
  assert_false(is_clear(verify(unit, cargos, forged, StowRules::default())))
}

///|
test "audit: support ratios handle pallet footprints above two square metres" {
  let cargos = [
    Cargo::new("BASE", Dimensions::new(2400, 1200, 400), 1000),
    Cargo::new("TOP", Dimensions::new(2400, 1200, 400), 1000),
  ]
  let unit = {
    ..LoadUnit::container_20ft("C"),
    dims: Dimensions::new(2400, 1200, 1500),
    floor_limit_g_per_m2: 0,
  }
  let placements = [
    audit_placement(cargos, 0, 0, 0, 1),
    audit_placement(cargos, 1, 0, 400, 2),
  ]
  assert_false(
    has_hazard_kind(
      verify(unit, cargos, placements, StowRules::default()),
      InsufficientSupport,
    ),
  )
  assert_eq(
    pack_ordered(unit, cargos, StowRules::default(), [0, 1]).placements.length(),
    2,
  )
}

///|
test "audit: malformed manual placements return diagnostics without indexing crashes" {
  let cargos = [Cargo::new("BASE", Dimensions::new(400, 400, 400), 1000)]
  let base = audit_placement(cargos, 0, 0, 0, 1)
  let unknown = {
    ..base,
    cargo_id: "UNKNOWN",
    cargo_index: 99,
    layer: 2,
    box: Aabb::at(0, 0, 400, cargos[0].dims),
  }
  let unit = LoadUnit::container_20ft("C")
  assert_true(
    has_hazard_kind(
      verify(unit, cargos, [base, unknown], StowRules::default()),
      UnknownCargo,
    ),
  )
  let zero = { ..base, box: Aabb::at(0, 0, 0, Dimensions::new(400, 400, 0)), }
  assert_true(
    has_hazard_kind(
      verify(unit, cargos, [zero, zero], StowRules::default()),
      InputInvalid,
    ),
  )
}

///|
test "audit: invalid inputs and stale axle tare are blocked before arithmetic" {
  let unit = LoadUnit::container_20ft("C")
  let bad = [Cargo::new("NEGATIVE", Dimensions::new(400, 400, 400), -1000)]
  assert_eq(pack(unit, bad, StowRules::default()).placements.length(), 0)
  assert_true(
    has_hazard_kind(verify(unit, bad, [], StowRules::default()), InputInvalid),
  )
  let truck = LoadUnit::truck_rigid("T").with_axles([
    Axle::new(1000, 10_000_000),
  ])
  assert_false(is_clear(validate_input(truck, [], StowRules::default())))
  let duplicate = [
    Cargo::new("A", Dimensions::new(100, 100, 100), 0),
    Cargo::new("A", Dimensions::new(100, 100, 100), 0),
  ]
  assert_eq(pack(unit, duplicate, StowRules::default()).placements.length(), 0)
  let too_heavy = [
    Cargo::new("A", Dimensions::new(100, 100, 100), 1_500_000_000),
    Cargo::new("B", Dimensions::new(100, 100, 100), 1_500_000_000),
  ]
  assert_false(is_clear(validate_input(unit, too_heavy, StowRules::default())))
}

///|
test "audit: tare axle loads and high floor pressure are included" {
  let unit = LoadUnit::truck_rigid("T")
  let loads = axle_loads(unit, [], [])
  assert_eq(loads[0], 4_000_000)
  assert_eq(loads[1], 8_000_000)
  let cargos = [
    Cargo::new("BASE", Dimensions::new(100, 100, 100), 1000),
    Cargo::new("UPPER", Dimensions::new(100, 100, 100), 1000),
  ]
  let placed = [
    audit_placement(cargos, 0, 0, 0, 1),
    audit_placement(cargos, 1, 0, 100, 2),
  ]
  assert_eq(max_floor_pressure(placed, cargos), 200_000)
  assert_true(
    has_hazard_kind(
      verify(
        { ..LoadUnit::pallet_eur("P"), floor_limit_g_per_m2: 150_000, },
        cargos,
        placed,
        StowRules::default(),
      ),
      FloorLimitExceeded,
    ),
  )
}

///|
test "audit: explicit order cannot silently omit or duplicate goods" {
  let cargos = [
    Cargo::new("A", Dimensions::new(200, 200, 200), 1000),
    Cargo::new("B", Dimensions::new(200, 200, 200), 1000),
  ]
  let unit = LoadUnit::container_20ft("C")
  let plan = pack_ordered(unit, cargos, StowRules::default(), [0, 0, -1, 99])
  assert_eq(plan.placements.length(), 1)
  assert_eq(plan.unplaced.length(), 1)
  assert_eq(plan.unplaced[0].cargo_id, "B")
  assert_false(is_clear(plan.violations))
}

///|
test "audit: strict job parsing rejects numeric and option errors" {
  for
    body in [
      "\"size\":[100,100,100,100]", "\"size\":[100.5,100,100]", "\"size\":[100000,100,100]",
      "\"size\":[100,100,100],\"weight_kg\":-1", "\"size\":[100,100,100],\"weight_kg\":\"10\"",
      "\"size\":[100,100,100],\"upright\":\"typo\"", "\"size\":[100,100,100],\"fragile\":\"true\"",
      "\"size\":[100,100,100],\"stop\":-1", "\"size\":[100,100,100],\"gap_mm\":40000",
    ] {
    assert_true(
      parse_scenario(
        "{\"unit\":{\"type\":\"pallet_eur\"},\"items\":[{\"id\":\"A\"," +
        body +
        "}]}",
      )
      is Err(_),
    )
  }
  assert_true(
    parse_scenario(
      "{\"unit\":{\"type\":\"pallet_eur\"},\"items\":[],\"rules\":{\"min_support_permille\":2000}}",
    )
    is Err(_),
  )
  assert_true(
    parse_scenario(
      "{\"unit\":{\"type\":\"pallet_eur\"},\"items\":[],\"rules\":{\"axles\":\"false\"}}",
    )
    is Err(_),
  )
}

///|
test "audit: missing items and volumetric units have explicit semantics" {
  assert_eq(
    LoadUnit::container_20ft("C").capacity_m3(),
    LoadUnit::container_20ft("C").capacity_mm3(),
  )
  assert_eq(volumetric_weight_g(Dimensions::new(1, 1, 1)), 1)
  let cargos = [Cargo::new("A", Dimensions::new(100, 100, 100), 0)]
  assert_false(
    is_clear(
      verify(LoadUnit::container_20ft("C"), cargos, [], StowRules::default()),
    ),
  )
}
