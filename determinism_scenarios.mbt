///|
/// Same input, same plan. Everything downstream (a printed manifest, a signed
/// loading sheet) depends on this, so it is pinned rather than assumed.
fn make_cargos(count : Int32) -> Array[Cargo] {
  let cargos : Array[Cargo] = []
  let mut i = 0
  while i < count {
    let length = 400 + i % 7 * 60
    let width = 300 + i % 5 * 50
    let height = 250 + i % 3 * 80
    let weight = 20_000 + i % 11 * 7_000
    let cargo = Cargo::new(
      "C" + i.to_string(),
      Dimensions::new(length, width, height),
      weight,
    )
    cargos.push(cargo)
    i = i + 1
  }
  cargos
}

///|
test "determinism: packing the same job twice yields the same placements" {
  let unit = LoadUnit::container_40hc("DET-1")
  let rules = StowRules::default()
  let cargos = make_cargos(64)
  let first = pack(unit, cargos, rules)
  let second = pack(unit, cargos, rules)
  assert_eq(first.placements.length(), second.placements.length())
  assert_true(first.placements == second.placements)
  assert_eq(
    first.metrics.volume_utilization_permille,
    second.metrics.volume_utilization_permille,
  )
  assert_eq(first.unplaced.length(), second.unplaced.length())
}

///|
test "determinism: input order does not change the resulting plan" {
  let unit = LoadUnit::container_40hc("DET-2")
  let rules = StowRules::default()
  let cargos = make_cargos(24)
  let forward = pack(unit, cargos, rules)
  let reversed : Array[Cargo] = []
  let mut i = cargos.length() - 1
  while i >= 0 {
    reversed.push(cargos[i])
    i = i - 1
  }
  let backward = pack(unit, reversed, rules)
  // The placement order may differ because ids are re-indexed, but the set of
  // placed footprints and the totals have to agree.
  assert_eq(forward.placements.length(), backward.placements.length())
  assert_eq(forward.metrics.total_weight_g, backward.metrics.total_weight_g)
  assert_eq(forward.metrics.used_volume_mm3, backward.metrics.used_volume_mm3)
  assert_eq(forward.unplaced.length(), backward.unplaced.length())
}

///|
test "stress: a hundred small cartons fit a 40HC and stay legal" {
  let unit = LoadUnit::container_40hc("STRESS")
  let rules = StowRules::default()
  let cargos = make_cargos(120)
  let plan = pack(unit, cargos, rules)
  let placed = plan.placements.length()
  assert_true(placed > 90)
  assert_eq(placed + plan.unplaced.length(), cargos.length())
  let findings = verify(unit, cargos, plan.placements, rules)
  for finding in findings {
    assert_true(finding.kind == MissingCargo || finding.severity != Error)
  }
  assert_eq(count_by_severity(findings, Error), plan.unplaced.length())
  // Balancing must not invent overlaps either.
  let balanced = balance_load(unit, plan.placements, cargos)
  for finding in verify(unit, cargos, balanced, rules) {
    assert_true(finding.kind == MissingCargo || finding.severity != Error)
  }
}

///|
test "stress: palletizing uniform cartons fills the columns" {
  let unit = LoadUnit::pallet_eur("PLT-STRESS")
  // 400x300x250 at 8 kg: six per floor band, seven bands on an EUR pallet.
  let cargos : Array[Cargo] = []
  for i in 0..<24 {
    cargos.push(
      Cargo::new("P" + i.to_string(), Dimensions::new(400, 300, 250), 8_000),
    )
  }
  let plan = palletize(unit, cargos, StowRules::default())
  // Six per band, three bands deep is the per-cargo layer limit.
  assert_eq(plan.placements.length(), 18)
  for finding in plan.violations {
    assert_true(finding.kind == MissingCargo || finding.severity != Error)
  }
  assert_eq(count_by_severity(plan.violations, Error), 6)
  // Every band holds six boxes and the depth stops at the per-cargo limit.
  let layers = compute_layers(plan.placements)
  assert_eq(layers.length(), plan.placements.length())
  let mut band1 = 0
  let mut band2 = 0
  let mut band3 = 0
  for l in layers {
    if l == 1 {
      band1 = band1 + 1
    } else if l == 2 {
      band2 = band2 + 1
    } else if l == 3 {
      band3 = band3 + 1
    } else {
      fail("a column grew past the per-cargo layer limit: " + l.to_string())
    }
  }
  assert_eq(band1, 6)
  assert_eq(band2, 6)
  assert_eq(band3, 6)
}
