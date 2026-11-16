///|
/// One cargo box in its final position. `layer` is the 1-based height layer of
/// the stack the box belongs to, which is what a loader reads first.
pub(all) struct Placement {
  cargo_id : String
  cargo_index : Int32
  orientation : Orientation
  box : Aabb
  stop : Int32
  layer : Int32
} derive(Eq)

///|
pub(all) struct Unplaced {
  cargo_id : String
  reason : String
} derive(Eq)

///|
/// Derived numbers for a plan. Every field is computed from the placements, so a
/// hand edited plan can be re-scored and compared with the automatic one.
pub(all) struct PlanMetrics {
  placed_count : Int32
  cargo_count : Int32
  used_volume_mm3 : Int64
  capacity_volume_mm3 : Int64
  volume_utilization_permille : Int32
  total_weight_g : Int32
  payload_limit_g : Int32
  weight_utilization_permille : Int32
  floor_used_mm2 : Int64
  floor_utilization_permille : Int32
  cog_x_mm : Int32
  cog_y_mm : Int32
  cog_z_mm : Int32
  stack_height_mm : Int32
  stop_weight_g : Array[(Int32, Int32)]
} derive(Eq)

///|
/// A complete loading plan: what goes where, what did not fit, its metrics and
/// any rule violations found by the verifier.
pub(all) struct LoadPlan {
  unit_id : String
  unit_kind : UnitKind
  placements : Array[Placement]
  unplaced : Array[Unplaced]
  metrics : PlanMetrics
  violations : Array[Violation]
} derive(Eq)

///|
pub fn Placement::footprint_mm2(self : Placement) -> Int64 {
  self.box.size.length.to_int64() * self.box.size.width.to_int64()
}

///|
pub fn Placement::top_z(self : Placement) -> Int32 {
  self.box.max_z()
}

///|
/// Weighted centre of gravity of the placed cargo. `None` when nothing is loaded.
pub fn center_of_gravity(
  placements : Array[Placement],
  cargos : Array[Cargo],
) -> Point3? {
  let mut wx = 0L
  let mut wy = 0L
  let mut wz = 0L
  let mut w = 0L
  for p in placements {
    if p.cargo_index >= 0 && p.cargo_index < cargos.length() {
      let c = cargos[p.cargo_index]
      let g = c.weight_g.to_int64()
      wx = wx + g * p.box.center_x().to_int64()
      wy = wy + g * p.box.center_y().to_int64()
      wz = wz + g * p.box.center_z().to_int64()
      w = w + g
    }
  }
  if w == 0L {
    return None
  }
  Some({ x: (wx / w).to_int(), y: (wy / w).to_int(), z: (wz / w).to_int(), })
}

///|
/// Floor area actually touched by cargo, computed as the union area of the
/// footprints of everything standing on the floor. A simple sweep over the X
/// axis keeps it exact for the non-overlapping rectangles a verified plan has.
pub fn floor_used_area(placements : Array[Placement]) -> Int64 {
  let mut total = 0L
  for p in placements {
    if p.box.min.z == 0 {
      total = total + p.footprint_mm2()
    }
  }
  total
}

///|
/// Sum of the weights that rest directly on `index`.
pub fn load_on(
  placements : Array[Placement],
  cargos : Array[Cargo],
  index : Int32,
) -> Int32 {
  let target = placements[index]
  let mut load = 0
  for i in 0..<placements.length() {
    if i != index {
      let other = placements[i]
      if other.box.min.z == target.box.max_z() &&
        other.box.footprint_overlap(target.box) > 0 {
        load = load + cargos[other.cargo_index].weight_g
      }
    }
  }
  load
}

///|
/// 1-based layer of the stack a box belongs to: one more than the deepest support
/// below it. Floor standing boxes are layer 1.
pub fn layer_of(placements : Array[Placement], index : Int32) -> Int32 {
  let target = placements[index]
  let mut deepest = 0
  let mut supported = false
  for i in 0..<placements.length() {
    if i != index {
      let other = placements[i]
      if other.box.max_z() == target.box.min.z &&
        other.box.footprint_overlap(target.box) > 0 {
        deepest = max_i(deepest, layer_of(placements, i))
        supported = true
      }
    }
  }
  if supported {
    deepest + 1
  } else {
    1
  }
}

///|
/// Recompute every metric of a plan from its placements.
pub fn compute_metrics(
  unit : LoadUnit,
  cargos : Array[Cargo],
  placements : Array[Placement],
) -> PlanMetrics {
  let envelope = unit.envelope()
  let mut used_volume = 0L
  let mut weight = 0
  let mut height = 0
  for p in placements {
    used_volume = used_volume + p.box.volume_mm3()
    if p.cargo_index >= 0 && p.cargo_index < cargos.length() {
      weight = weight + cargos[p.cargo_index].weight_g
    }
    height = max_i(height, p.box.max_z())
  }
  let cog = match center_of_gravity(placements, cargos) {
    Some(p) => p
    None => Point3::new(0, 0, 0)
  }
  let capacity = envelope.volume_mm3()
  let floor_total = floor_area_mm2(envelope)
  let floor_used = floor_used_area(placements)
  PlanMetrics::{
    placed_count: placements.length(),
    cargo_count: cargos.length(),
    used_volume_mm3: used_volume,
    capacity_volume_mm3: capacity,
    volume_utilization_permille: ratio_permille(used_volume, capacity),
    total_weight_g: weight,
    payload_limit_g: unit.max_payload_g,
    weight_utilization_permille: ratio_permille(
      weight.to_int64(),
      unit.max_payload_g.to_int64(),
    ),
    floor_used_mm2: floor_used,
    floor_utilization_permille: ratio_permille(floor_used, floor_total),
    cog_x_mm: cog.x,
    cog_y_mm: cog.y,
    cog_z_mm: cog.z,
    stack_height_mm: height,
    stop_weight_g: stop_weights(placements, cargos),
  }
}

///|
/// Weight per delivery stop, ascending by stop number. This is what the driver
/// sees on the manifest and what a multi-stop packer optimises against.
pub fn stop_weights(
  placements : Array[Placement],
  cargos : Array[Cargo],
) -> Array[(Int32, Int32)] {
  let stops : Array[Int32] = []
  for p in placements {
    let stop = p.stop
    let mut seen = false
    for s in stops {
      if s == stop {
        seen = true
      }
    }
    if !seen {
      stops.push(stop)
    }
  }
  sort_ints(stops)
  let out : Array[(Int32, Int32)] = []
  for s in stops {
    let mut grams = 0
    for p in placements {
      if p.stop == s && p.cargo_index >= 0 && p.cargo_index < cargos.length() {
        grams = grams + cargos[p.cargo_index].weight_g
      }
    }
    out.push((s, grams))
  }
  out
}

///|
/// Insertion sort for the small integer arrays used in reports. Keeping our own
/// sort avoids any dependency on the ordering stability of a library routine.
pub fn sort_ints(values : Array[Int32]) -> Unit {
  let n = values.length()
  let mut i = 1
  while i < n {
    let key = values[i]
    let mut j = i - 1
    let mut done = false
    while j >= 0 && !done {
      if values[j] > key {
        values[j + 1] = values[j]
        j = j - 1
      } else {
        done = true
      }
    }
    values[j + 1] = key
    i = i + 1
  }
}

///|
test "plan: metrics of one box" {
  let unit = LoadUnit::container_20ft("C1")
  let cargo = Cargo::new("A", Dimensions::new(1000, 1000, 1000), 24_000)
  let cargos = [cargo]
  let placement = Placement::{
    cargo_id: "A",
    cargo_index: 0,
    orientation: LWH,
    box: Aabb::at(0, 0, 0, Dimensions::new(1000, 1000, 1000)),
    stop: 0,
    layer: 1,
  }
  let metrics = compute_metrics(unit, cargos, [placement])
  assert_eq(metrics.placed_count, 1)
  assert_eq(metrics.total_weight_g, 24_000)
  assert_eq(metrics.cog_x_mm, 500)
  assert_eq(metrics.stack_height_mm, 1000)
  assert_eq(metrics.stop_weight_g.length(), 1)
}

///|
test "plan: floor area only counts floor standing boxes" {
  let cargos = [
    Cargo::new("A", Dimensions::new(1000, 1000, 500), 10_000),
    Cargo::new("B", Dimensions::new(1000, 1000, 500), 10_000),
  ]
  let placements = [
    Placement::{
      cargo_id: "A",
      cargo_index: 0,
      orientation: LWH,
      box: Aabb::at(0, 0, 0, Dimensions::new(1000, 1000, 500)),
      stop: 0,
      layer: 1,
    },
    Placement::{
      cargo_id: "B",
      cargo_index: 1,
      orientation: LWH,
      box: Aabb::at(0, 0, 500, Dimensions::new(1000, 1000, 500)),
      stop: 0,
      layer: 2,
    },
  ]
  assert_eq(floor_used_area(placements), 1_000_000L)
  assert_eq(layer_of(placements, 1), 2)
  assert_eq(load_on(placements, cargos, 0), 10_000)
}

///|
pub extend Placement with Eq::{equal, not_equal}

///|
pub extend Unplaced with Eq::{equal, not_equal}

///|
pub extend PlanMetrics with Eq::{equal, not_equal}

///|
pub extend LoadPlan with Eq::{equal, not_equal}
