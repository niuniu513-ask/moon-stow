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
