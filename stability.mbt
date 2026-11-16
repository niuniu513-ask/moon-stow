///|
/// Load share on each axle, in grams. Weights are distributed between the two
/// axles that bracket a box's centre, with a linear lever rule; boxes outside the
/// axle span load the nearest axle fully, which is what a planner assumes when
/// the box overhangs the last axle.
pub fn axle_loads(
  unit : LoadUnit,
  placements : Array[Placement],
  cargos : Array[Cargo],
) -> Array[Int32] {
  let loads : Array[Int32] = []
  for _ in unit.axles {
    loads.push(0)
  }
  if unit.axles.length() == 0 {
    return loads
  }
  for p in placements {
    if p.cargo_index < 0 || p.cargo_index >= cargos.length() {
      continue
    }
    let weight = cargos[p.cargo_index].weight_g
    let x = p.box.center_x()
    let mut placed = false
    let mut i = 0
    while i + 1 < unit.axles.length() && !placed {
      let a = unit.axles[i]
      let b = unit.axles[i + 1]
      if x >= a.position_mm && x <= b.position_mm {
        let span = max_i(1, b.position_mm - a.position_mm)
        let to_b = weight * (x - a.position_mm) / span
        loads[i] = loads[i] + (weight - to_b)
        loads[i + 1] = loads[i + 1] + to_b
        placed = true
      }
      i = i + 1
    }
    if !placed {
      let first = unit.axles[0]
      if x < first.position_mm {
        loads[0] = loads[0] + weight
      } else {
        loads[unit.axles.length() - 1] = loads[unit.axles.length() - 1] + weight
      }
    }
  }
  loads
}

///|
/// Largest floor pressure produced by a single box, in grams per square metre.
/// A container floor or a truck bed gives way under a point load long before the
/// payload limit is reached, which is why this is a separate check.
pub fn max_floor_pressure(
  placements : Array[Placement],
  cargos : Array[Cargo],
) -> Int32 {
  let mut worst = 0
  for p in placements {
    if p.box.min.z != 0 || p.cargo_index < 0 || p.cargo_index >= cargos.length() {
      continue
    }
    let area_m2 = p.footprint_mm2()
    if area_m2 <= 0L {
      continue
    }
    let weight = cargos[p.cargo_index].weight_g.to_int64()
    let pressure = weight * 1_000_000L / area_m2
    worst = max_i(worst, pressure.to_int())
  }
  worst
}

///|
/// Permille deviation of the centre of gravity from the geometric centre of the
/// floor, per axis, relative to half the dimension. 0 means perfectly centred.
pub fn cog_offset_permille(
  cog : Point3,
  envelope : Dimensions,
) -> (Int32, Int32) {
  let half_x = max_i(1, envelope.length / 2)
  let half_y = max_i(1, envelope.width / 2)
  let dx = (cog.x - envelope.length / 2).to_int64()
  let dy = (cog.y - envelope.width / 2).to_int64()
  let px = (dx * 1000L / half_x.to_int64()).to_int()
  let py = (dy * 1000L / half_y.to_int64()).to_int()
  (px, py)
}

///|
/// Whether the plan tips over the rear or front edge: the centre of gravity must
/// project inside the floor rectangle, otherwise the unit is unstable by
/// definition.
pub fn cog_inside_floor(cog : Point3, envelope : Dimensions) -> Bool {
  cog.x >= 0 &&
  cog.x <= envelope.length &&
  cog.y >= 0 &&
  cog.y <= envelope.width
}

///|
/// Clamp a wanted shift between the free space on the two sides of the load.
fn shift_towards(target : Int32, low : Int32, high : Int32) -> Int32 {
  if low > high {
    0
  } else {
    clamp_int(target, low, high)
  }
}

///|
/// Horizontal shift, in millimetres, that moves the centre of gravity onto the
/// balancing point without pushing any box through a wall. The balancing point is
/// the middle of the wheelbase when the unit carries axles (a truck wants its
/// weight between the wheels, not in the middle of the bed) and the middle of the
/// floor otherwise. The shift is clamped to the free space, so a load already
/// standing against the door end only moves away from it.
pub fn balance_shift(
  unit : LoadUnit,
  placements : Array[Placement],
  cargos : Array[Cargo],
) -> (Int32, Int32) {
  if placements.length() == 0 {
    return (0, 0)
  }
  let mut total = 0L
  let mut moment_x = 0L
  let mut moment_y = 0L
  let mut min_x = placements[0].box.min.x
  let mut max_x = placements[0].box.max_x()
  let mut min_y = placements[0].box.min.y
  let mut max_y = placements[0].box.max_y()
  for p in placements {
    let weight = if p.cargo_index >= 0 && p.cargo_index < cargos.length() {
      cargos[p.cargo_index].weight_g.to_int64()
    } else {
      0L
    }
    total = total + weight
    moment_x = moment_x + weight * p.box.center_x().to_int64()
    moment_y = moment_y + weight * p.box.center_y().to_int64()
    min_x = min_i(min_x, p.box.min.x)
    max_x = max_i(max_x, p.box.max_x())
    min_y = min_i(min_y, p.box.min.y)
    max_y = max_i(max_y, p.box.max_y())
  }
  if total <= 0L {
    return (0, 0)
  }
  let env = unit.envelope()
  let cog_x = (moment_x / total).to_int()
  let cog_y = (moment_y / total).to_int()
  let last_axle = unit.axles.length() - 1
  let target_x = if unit.axles.length() >= 2 {
    (unit.axles[0].position_mm + unit.axles[last_axle].position_mm) / 2
  } else {
    env.length / 2
  }
  let dx = shift_towards(target_x - cog_x, -min_x, env.length - max_x)
  let dy = shift_towards(env.width / 2 - cog_y, -min_y, env.width - max_y)
  (dx, dy)
}

///|
/// Slide the whole load to the balanced position. Only the absolute coordinates
/// change, so support, stacking, segregation and overstow stay as they were, and
/// the centre of gravity lands in the middle of the floor instead of in whatever
/// corner the packer started from.
pub fn balance_load(
  unit : LoadUnit,
  placements : Array[Placement],
  cargos : Array[Cargo],
) -> Array[Placement] {
  let (dx, dy) = balance_shift(unit, placements, cargos)
  if dx == 0 && dy == 0 {
    return placements.copy()
  }
  let out : Array[Placement] = []
  for p in placements {
    out.push({
      ..p,
      box: Aabb::at(p.box.min.x + dx, p.box.min.y + dy, p.box.min.z, p.box.size),
    })
  }
  out
}

///|
test "stability: balancing slides a corner load to the middle" {
  let unit = LoadUnit::container_20ft("C1")
  let cargos = [Cargo::new("A", Dimensions::new(1000, 800, 900), 5_000)]
  let placements = [
    Placement::{
      cargo_id: "A",
      cargo_index: 0,
      orientation: LWH,
      box: Aabb::at(0, 0, 0, Dimensions::new(1000, 800, 900)),
      stop: 0,
      layer: 1,
    },
  ]
  let (dx, dy) = balance_shift(unit, placements, cargos)
  assert_true(dx > 0 && dy > 0)
  let balanced = balance_load(unit, placements, cargos)
  let cog = center_of_gravity(balanced, cargos).unwrap()
  let (px, py) = cog_offset_permille(cog, unit.envelope())
  assert_true(px >= -1 && px <= 1)
  assert_true(py >= -1 && py <= 1)
  assert_true(is_clear(verify(unit, cargos, balanced, StowRules::default())))
}

///|
test "stability: a truck balances over its wheelbase" {
  let unit = LoadUnit::truck_rigid("T1")
  let cargos = [Cargo::new("A", Dimensions::new(1000, 1000, 800), 4_000)]
  let placements = [
    Placement::{
      cargo_id: "A",
      cargo_index: 0,
      orientation: LWH,
      box: Aabb::at(0, 0, 0, Dimensions::new(1000, 1000, 800)),
      stop: 0,
      layer: 1,
    },
  ]
  let balanced = balance_load(unit, placements, cargos)
  let axle_centre = (unit.axles[0].position_mm + unit.axles[1].position_mm) / 2
  assert_eq(balanced[0].box.center_x(), axle_centre)
}

///|
test "stability: a load against the wall only moves inward" {
  let unit = LoadUnit::container_20ft("C1")
  let cargos = [Cargo::new("A", Dimensions::new(5898, 2352, 900), 5_000)]
  let placements = [
    Placement::{
      cargo_id: "A",
      cargo_index: 0,
      orientation: LWH,
      box: Aabb::at(0, 0, 0, Dimensions::new(5898, 2352, 900)),
      stop: 0,
      layer: 1,
    },
  ]
  let (dx, dy) = balance_shift(unit, placements, cargos)
  assert_eq(dx, 0)
  assert_eq(dy, 0)
}

///|
test "stability: centred load has no offset" {
  let envelope = Dimensions::new(5898, 2352, 2393)
  let cog = Point3::new(2949, 1176, 500)
  let (px, py) = cog_offset_permille(cog, envelope)
  assert_eq(px, 0)
  assert_eq(py, 0)
  assert_true(cog_inside_floor(cog, envelope))
}

///|
test "stability: lever rule splits weight" {
  let unit = LoadUnit::truck_rigid("T1")
  let cargos = [Cargo::new("A", Dimensions::new(1000, 1000, 1000), 10_000)]
  let placements = [
    Placement::{
      cargo_id: "A",
      cargo_index: 0,
      orientation: LWH,
      box: Aabb::at(5_700, 0, 0, Dimensions::new(1000, 1000, 1000)),
      stop: 0,
      layer: 1,
    },
  ]
  let loads = axle_loads(unit, placements, cargos)
  assert_eq(loads.length(), 2)
  assert_eq(loads[0] + loads[1], 10_000)
  assert_true(loads[0] >= 4_000 && loads[0] <= 6_000)
}
