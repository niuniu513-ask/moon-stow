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

///|
/// Deterministic mixed cartons used by the quality tests: five footprints, three
/// delivery stops, four layers allowed, no hazard. Kept small so the suite stays
/// fast while still exercising stacking and the retry passes.
fn quality_set(count : Int32) -> Array[Cargo] {
  let sizes : Array[(Int32, Int32, Int32)] = [
    (800, 600, 500),
    (400, 300, 300),
    (1200, 800, 600),
    (600, 400, 400),
    (500, 400, 350),
  ]
  let out : Array[Cargo] = []
  let mut s = 12_345
  for i in 0..<count {
    s = (s * 1103515245 + 12345) & 0x7fffffff
    let (l, w, h) = sizes[(s % 5).to_int()]
    s = (s * 1103515245 + 12345) & 0x7fffffff
    let stop = 1 + (s % 3).to_int()
    out.push(
      Cargo::new(
        "Q" + i.to_string(),
        Dimensions::new(l, w, h),
        l * w * h / 1_000_000 * 120,
      )
      .with_stop(stop)
      .with_stack_limit(4, 400_000),
    )
  }
  out
}

///|
test "pack_best: never places fewer pieces than pack" {
  let unit = LoadUnit::container_20ft("QB1")
  let cargos = quality_set(24)
  let rules = StowRules::default()
  let base = pack(unit, cargos, rules)
  let best = pack_best(unit, cargos, rules)
  assert_true(best.metrics.placed_count >= base.metrics.placed_count)
  assert_eq(
    best.unplaced.length(),
    cargos.length() - best.metrics.placed_count.to_int(),
  )
  // the quality plan must survive its own verifier, retries included
  assert_true(is_clear(verify(unit, cargos, best.placements, rules)))
}

///|
test "pack_best: same input prints the same plan" {
  let unit = LoadUnit::container_20ft("QB2")
  let cargos = quality_set(18)
  let rules = StowRules::default()
  let first = render_text(pack_best(unit, cargos, rules), cargos)
  let second = render_text(pack_best(unit, cargos, rules), cargos)
  assert_eq(first, second)
}

///|
test "order: every key is a permutation and sorts the way it claims" {
  let cargos = quality_set(12)
  for key in OrderKey::all() {
    let order = order_cargos_by(cargos, key)
    assert_eq(order.length(), cargos.length())
    let seen : Array[Int32] = []
    for i in order {
      assert_true(i >= 0 && i < cargos.length())
      let mut dup = false
      for v in seen {
        if v == i {
          dup = true
        }
      }
      assert_false(dup)
      seen.push(i)
    }
  }
  let desc = order_cargos_by(cargos, VolumeDesc)
  let mut k = 1
  while k < desc.length() {
    assert_true(
      cargos[desc[k - 1]].dims.volume_mm3() >= cargos[desc[k]].dims.volume_mm3(),
    )
    k = k + 1
  }
  let asc = order_cargos_by(cargos, VolumeAsc)
  let mut j = 1
  while j < asc.length() {
    assert_true(
      cargos[asc[j - 1]].dims.volume_mm3() <= cargos[asc[j]].dims.volume_mm3(),
    )
    j = j + 1
  }
}

///|
test "plan: overlapping floor footprints are counted once" {
  let overlap_x : Array[Placement] = [
    {
      cargo_id: "A",
      cargo_index: 0,
      orientation: LWH,
      box: Aabb::at(0, 0, 0, Dimensions::new(1000, 1000, 500)),
      stop: 0,
      layer: 1,
    },
    {
      cargo_id: "B",
      cargo_index: 1,
      orientation: LWH,
      box: Aabb::at(500, 0, 0, Dimensions::new(1000, 1000, 500)),
      stop: 0,
      layer: 1,
    },
  ]
  assert_eq(floor_used_area(overlap_x), 1_500_000L)
  let overlap_y : Array[Placement] = [
    {
      cargo_id: "A",
      cargo_index: 0,
      orientation: LWH,
      box: Aabb::at(0, 0, 0, Dimensions::new(1000, 1000, 500)),
      stop: 0,
      layer: 1,
    },
    {
      cargo_id: "C",
      cargo_index: 2,
      orientation: LWH,
      box: Aabb::at(0, 500, 0, Dimensions::new(1000, 1000, 500)),
      stop: 0,
      layer: 1,
    },
  ]
  assert_eq(floor_used_area(overlap_y), 1_500_000L)
  // disjoint footprints still add up
  let disjoint : Array[Placement] = [
    {
      cargo_id: "A",
      cargo_index: 0,
      orientation: LWH,
      box: Aabb::at(0, 0, 0, Dimensions::new(1000, 1000, 500)),
      stop: 0,
      layer: 1,
    },
    {
      cargo_id: "B",
      cargo_index: 1,
      orientation: LWH,
      box: Aabb::at(1000, 0, 0, Dimensions::new(1000, 1000, 500)),
      stop: 0,
      layer: 1,
    },
  ]
  assert_eq(floor_used_area(disjoint), 2_000_000L)
  // a box carried by another one adds no floor area at all
  let stacked : Array[Placement] = [
    {
      cargo_id: "A",
      cargo_index: 0,
      orientation: LWH,
      box: Aabb::at(0, 0, 0, Dimensions::new(1000, 1000, 500)),
      stop: 0,
      layer: 1,
    },
    {
      cargo_id: "B",
      cargo_index: 1,
      orientation: LWH,
      box: Aabb::at(0, 0, 500, Dimensions::new(1000, 1000, 500)),
      stop: 0,
      layer: 2,
    },
  ]
  assert_eq(floor_used_area(stacked), 1_000_000L)
}

///|
/// Does the plan carry a finding of this kind?
fn carries(violations : Array[Violation], kind : ViolationKind) -> Bool {
  for v in violations {
    if v.kind == kind {
      return true
    }
  }
  false
}

///|
test "pack: layers are re-derived from the finished support graph" {
  // A stands on the floor; D carries C so that C's top face lands at exactly the
  // same height as A's. TOP was placed when A was its only support, which is one
  // layer too low once C is under it as well.
  let cargos : Array[Cargo] = [
    Cargo::new("A", Dimensions::new(1000, 1000, 500), 50_000),
    Cargo::new("D", Dimensions::new(1000, 1000, 250), 25_000),
    Cargo::new("C", Dimensions::new(1000, 1000, 250), 25_000),
    Cargo::new("TOP", Dimensions::new(2000, 1000, 500), 100_000),
  ]
  let placements : Array[Placement] = [
    {
      cargo_id: "A",
      cargo_index: 0,
      orientation: LWH,
      box: Aabb::at(0, 0, 0, Dimensions::new(1000, 1000, 500)),
      stop: 0,
      layer: 1,
    },
    {
      cargo_id: "D",
      cargo_index: 1,
      orientation: LWH,
      box: Aabb::at(1000, 0, 0, Dimensions::new(1000, 1000, 250)),
      stop: 0,
      layer: 1,
    },
    {
      cargo_id: "C",
      cargo_index: 2,
      orientation: LWH,
      box: Aabb::at(1000, 0, 250, Dimensions::new(1000, 1000, 250)),
      stop: 0,
      layer: 2,
    },
    {
      cargo_id: "TOP",
      cargo_index: 3,
      orientation: LWH,
      box: Aabb::at(0, 0, 500, Dimensions::new(2000, 1000, 500)),
      stop: 0,
      layer: 2,
    },
  ]
  let repaired = repair_layers(cargos, placements, StowRules::default())
  assert_eq(repaired.length(), 4)
  assert_eq(repaired[0].layer, 1)
  assert_eq(repaired[1].layer, 1)
  assert_eq(repaired[2].layer, 2)
  // the stale stamp is lifted: two supports, the deeper one wins
  assert_eq(repaired[3].layer, 3)
  // and the corrected plan is what the verifier expects
  let unit = LoadUnit::container_20ft("RESTAMP")
  let violations = verify(unit, cargos, repaired, StowRules::default())
  assert_false(carries(violations, PlacementMetadata))
}

///|
test "pack: a column taller than its own limit loses its top box" {
  let cap = 4
  let cargos : Array[Cargo] = []
  let placements : Array[Placement] = []
  for i in 0..<5 {
    let id = "K" + i.to_string()
    cargos.push(
      Cargo::new(id, Dimensions::new(1000, 1000, 500), 40_000).with_stack_limit(
        cap, 400_000,
      ),
    )
    placements.push({
      cargo_id: id,
      cargo_index: i,
      orientation: LWH,
      box: Aabb::at(0, 0, i * 500, Dimensions::new(1000, 1000, 500)),
      stop: 0,
      layer: i + 1,
    })
  }
  let repaired = repair_layers(cargos, placements, StowRules::default())
  assert_eq(repaired.length(), 4)
  assert_eq(repaired[3].cargo_id, "K3")
  for i in 0..<4 {
    assert_eq(repaired[i].layer, i + 1)
  }
  let unit = LoadUnit::container_20ft("PRUNE")
  assert_false(
    carries(
      verify(unit, cargos, repaired, StowRules::default()),
      StackLayersExceeded,
    ),
  )
}

///|
test "pack_stops: bands keep each stop usable and hand the rest out by volume" {
  let lengths = band_lengths(12_000, [3_000, 2_000, 1_000], [6L, 3L, 1L])
  assert_eq(lengths.length(), 3)
  assert_true(lengths[0] >= 3_000)
  assert_true(lengths[1] >= 2_000)
  assert_true(lengths[2] >= 1_000)
  let mut sum = 0
  for l in lengths {
    sum = sum + l
  }
  assert_eq(sum, 12_000)
  // surplus follows volume, so a busier stop ends up wider
  assert_true(lengths[0] > lengths[1])
  assert_true(lengths[1] > lengths[2])
  // when even the minimums do not fit, the length is shared instead of dropped
  let tight = band_lengths(3_000, [3_000, 2_000, 1_000], [1L, 1L, 1L])
  assert_eq(tight.length(), 3)
  let mut tight_sum = 0
  for l in tight {
    tight_sum = tight_sum + l
  }
  assert_true(tight_sum <= 3_000)
}

///|
test "pack: sectioned and interleaved plans both survive the audit" {
  let rules = StowRules::default()
  let cargos = quality_set(24)
  let units : Array[LoadUnit] = [
    LoadUnit::container_20ft("A20"),
    LoadUnit::container_40hc("A40"),
    LoadUnit::truck_rigid("T7"),
    LoadUnit::pallet_eur("E1"),
  ]
  for unit in units {
    let best = pack_best(unit, cargos, rules)
    assert_false(carries(best.violations, PlacementMetadata))
    assert_false(carries(best.violations, StackLayersExceeded))
    assert_eq(
      best.unplaced.length(),
      cargos.length() - best.metrics.placed_count.to_int(),
    )
    let sectioned = pack_stops(unit, cargos, rules)
    assert_false(carries(sectioned.violations, PlacementMetadata))
    assert_false(carries(sectioned.violations, StackLayersExceeded))
    // the sectioned mode is a candidate, never a regression
    assert_true(sectioned.metrics.placed_count >= best.metrics.placed_count)
    assert_eq(
      sectioned.unplaced.length(),
      cargos.length() - sectioned.metrics.placed_count.to_int(),
    )
  }
}

///|
test "pack_stops: a single stop is the interleaved plan" {
  let unit = LoadUnit::container_20ft("ONE")
  let rules = StowRules::default()
  let cargos = quality_set(12).map(fn(c) { c.with_stop(0) })
  let interleaved = pack_best(unit, cargos, rules)
  let sectioned = pack_stops(unit, cargos, rules)
  assert_eq(sectioned.metrics.placed_count, interleaved.metrics.placed_count)
  assert_eq(render_text(sectioned, cargos), render_text(interleaved, cargos))
}
