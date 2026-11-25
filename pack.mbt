///|
/// Internal packing state: one slot is a committed box plus the load it carries.
struct Slot {
  cargo_index : Int32
  box : Aabb
  orientation : Orientation
  layer : Int32
  mut load_on_top_g : Int32
}

///|
/// A candidate position for the item currently being placed, together with the
/// numbers the heuristic scores it by.
priv struct Candidate {
  box : Aabb
  orientation : Orientation
  layer : Int32
  support_permille : Int32
}

///|
/// Everything one packing run needs. Kept as a value so a caller can build a
/// context once and place several orders into the same unit.
pub struct Packer {
  unit : LoadUnit
  cargos : Array[Cargo]
  rules : StowRules
  envelope : Dimensions
  placed : Array[Slot]
  mut used_weight_g : Int32
}

///|
pub fn Packer::new(
  unit : LoadUnit,
  cargos : Array[Cargo],
  rules : StowRules,
) -> Packer {
  {
    unit,
    cargos,
    rules,
    envelope: unit.envelope(),
    placed: [],
    used_weight_g: 0,
  }
}

///|
/// Indices of the placed slots whose top face is exactly at the candidate's
/// bottom face and whose footprint overlaps it.
fn Packer::supports_of_box(self : Packer, box : Aabb) -> Array[Int32] {
  let out : Array[Int32] = []
  for i in 0..<self.placed.length() {
    let s = self.placed[i]
    if s.box.max_z() == box.min.z && s.box.footprint_overlap(box) > 0 {
      out.push(i)
    }
  }
  out
}

///|
/// 1-based layer of a candidate given its supports.
fn Packer::layer_for(self : Packer, supports : Array[Int32]) -> Int32 {
  let mut deepest = 0
  for s in supports {
    deepest = max_i(deepest, self.placed[s].layer)
  }
  if supports.length() == 0 {
    1
  } else {
    deepest + 1
  }
}

///|
fn Packer::ancestors(self : Packer, supports : Array[Int32]) -> Array[Int32] {
  let out : Array[Int32] = []
  for s in supports {
    out.push(s)
  }
  let mut cursor = 0
  while cursor < out.length() {
    let current = self.placed[out[cursor]]
    cursor = cursor + 1
    for i in 0..<self.placed.length() {
      let below = self.placed[i]
      if below.box.min.z < current.box.min.z &&
        below.box.max_z() == current.box.min.z &&
        below.box.footprint_overlap(current.box) > 0 {
        let mut seen = false
        for v in out {
          if v == i {
            seen = true
          }
        }
        if !seen {
          out.push(i)
        }
      }
    }
  }
  out
}

///|
/// May `cargo_index` be placed with exactly this box? Every rule that the
/// verifier checks is enforced here as well, so a plan that the packer produces
/// never fails its own audit.
fn Packer::fits(self : Packer, cargo_index : Int32, box : Aabb) -> Bool {
  if !box.fits_within(self.envelope) {
    return false
  }
  let cargo = self.cargos[cargo_index]
  // solid overlap
  for i in 0..<self.placed.length() {
    let other = self.cargos[self.placed[i].cargo_index]
    let required = max_i(cargo.min_gap_mm, other.min_gap_mm)
    // Same rule as verify: clearance is lateral, so it is only enforced against
    // cargo that shares a height band; stacking stays possible.
    if box.intersects(self.placed[i].box) ||
      (
        required > 0 &&
        box.shares_height(self.placed[i].box) &&
        box.side_gap(self.placed[i].box) < required
      ) {
      return false
    }
  }
  // support, stacking and top load
  let supports = self.supports_of_box(box)
  let layer = self.layer_for(supports)
  if box.min.z > 0 && supports.length() == 0 {
    return false
  }
  let own_area = box.size.length * box.size.width
  if own_area <= 0 {
    return false
  }
  if supports.length() > 0 {
    let below : Array[Aabb] = []
    for s in supports {
      below.push(self.placed[s].box)
    }
    let ratio = (box.supported_area(below).to_int64() *
    1000L /
    own_area.to_int64()).to_int()
    if ratio < self.rules.min_support_permille {
      return false
    }
    for s in self.ancestors(supports) {
      let slot = self.placed[s]
      let support_cargo = self.cargos[slot.cargo_index]
      if !support_cargo.stackable {
        return false
      }
      if layer > support_cargo.max_stack_layers {
        return false
      }
      if slot.load_on_top_g + cargo.weight_g > support_cargo.max_top_load_g {
        return false
      }
      if slot.box.min.z == 0 &&
        self.unit.floor_limit_g_per_m2 > 0 &&
        (
          support_cargo.weight_g.to_int64() +
          slot.load_on_top_g.to_int64() +
          cargo.weight_g.to_int64()
        ) *
        1_000_000L /
        floor_area_mm2(slot.box.size) >
        self.unit.floor_limit_g_per_m2.to_int64() {
        return false
      }
    }
  }
  if self.rules.max_stack_layers > 0 && layer > self.rules.max_stack_layers {
    return false
  }
  if layer > cargo.max_stack_layers {
    return false
  }
  // floor point load
  if box.min.z == 0 && self.unit.floor_limit_g_per_m2 > 0 {
    let pressure = cargo.weight_g.to_int64() * 1_000_000L / own_area.to_int64()
    if pressure > self.unit.floor_limit_g_per_m2.to_int64() {
      return false
    }
  }
  // payload
  if self.unit.max_payload_g > 0 &&
    self.used_weight_g + cargo.weight_g > self.unit.max_payload_g {
    return false
  }
  // overstow: nothing may end up in front of an earlier delivery
  if self.rules.enforce_overstow {
    for i in 0..<self.placed.length() {
      let slot = self.placed[i]
      let other_stop = self.cargos[slot.cargo_index].stop
      if other_stop == cargo.stop {
        continue
      }
      let overlap_y = min_i(box.max_y(), slot.box.max_y()) -
        max_i(box.min.y, slot.box.min.y)
      let overlap_z = min_i(box.max_z(), slot.box.max_z()) -
        max_i(box.min.z, slot.box.min.z)
      if overlap_y <= 0 || overlap_z <= 0 {
        continue
      }
      if other_stop < cargo.stop &&
        (if self.unit.rear_door_at_origin {
          box.min.x < slot.box.max_x()
        } else {
          box.max_x() > slot.box.min.x
        }) {
        return false
      }
      if other_stop > cargo.stop &&
        (if self.unit.rear_door_at_origin {
          box.max_x() > slot.box.min.x
        } else {
          box.min.x < slot.box.max_x()
        }) {
        return false
      }
    }
  }
  true
}

///|
/// Commit a candidate, keeping the load bookkeeping consistent.
fn Packer::commit(self : Packer, cargo_index : Int32, cand : Candidate) -> Unit {
  let cargo = self.cargos[cargo_index]
  let supports = self.supports_of_box(cand.box)
  for s in self.ancestors(supports) {
    self.placed[s].load_on_top_g = self.placed[s].load_on_top_g + cargo.weight_g
  }
  // The layer is derived from what actually carries the box. A caller may only
  // raise it, never lower it: a packer that passes layer 0 for every box would
  // otherwise hide a stack that is taller than the goods allow.
  self.placed.push({
    cargo_index,
    box: cand.box,
    orientation: cand.orientation,
    layer: max_i(self.layer_for(supports), cand.layer),
    load_on_top_g: 0,
  })
  self.used_weight_g = self.used_weight_g + cargo.weight_g
}

///|
/// Scoring: lowest layer first, then the best supported candidate, then the
/// position closest to the rear-left corner, then the declared orientation
/// order. Every tie is broken by a value, never by the order in which the
/// candidate list happens to be built, so the result is deterministic.
fn orientation_rank(o : Orientation) -> Int32 {
  match o {
    LWH => 0
    WLH => 1
    LHW => 2
    HLW => 3
    WHL => 4
    HWL => 5
  }
}

///|
fn better(a : Candidate, b : Candidate) -> Bool {
  if a.box.min.z != b.box.min.z {
    return a.box.min.z < b.box.min.z
  }
  if a.support_permille != b.support_permille {
    return a.support_permille > b.support_permille
  }
  if a.box.min.x != b.box.min.x {
    return a.box.min.x < b.box.min.x
  }
  if a.box.min.y != b.box.min.y {
    return a.box.min.y < b.box.min.y
  }
  orientation_rank(a.orientation) < orientation_rank(b.orientation)
}

///|
/// Add an extreme point unless it is outside the envelope or already present.
fn push_point(
  points : Array[Point3],
  p : Point3,
  envelope : Dimensions,
) -> Unit {
  if p.x < 0 ||
    p.y < 0 ||
    p.z < 0 ||
    p.x >= envelope.length ||
    p.y >= envelope.width ||
    p.z >= envelope.height {
    return
  }
  for q in points {
    if q.x == p.x && q.y == p.y && q.z == p.z {
      return
    }
  }
  points.push(p)
}

///|
/// Sort cargo indices by the deterministic key documented on `Cargo::sort_key`.
pub fn order_cargos(cargos : Array[Cargo]) -> Array[Int32] {
  let idx : Array[Int32] = []
  for i in 0..<cargos.length() {
    idx.push(i)
  }
  let keys : Array[String] = []
  for i in 0..<cargos.length() {
    keys.push(cargos[i].sort_key())
  }
  let n = idx.length()
  let mut i = 1
  while i < n {
    let key_i = keys[i]
    let idx_i = idx[i]
    let mut j = i - 1
    let mut done = false
    while j >= 0 && !done {
      if keys[j] > key_i {
        keys[j + 1] = keys[j]
        idx[j + 1] = idx[j]
        j = j - 1
      } else {
        done = true
      }
    }
    keys[j + 1] = key_i
    idx[j + 1] = idx_i
    i = i + 1
  }
  idx
}

///|
/// Pack every cargo into the unit in the given order. Items that cannot be
/// placed are reported with the reason, they are never silently dropped.

///|
/// Try to place one cargo at the best position currently reachable. Every
/// candidate comes from a point that a placed box already produced, so a
/// failure here means the item really has no room left, not that the search
/// gave up early.
fn place_one(
  packer : Packer,
  points : Array[Point3],
  cargo_index : Int32,
) -> Bool {
  if cargo_index < 0 || cargo_index >= packer.cargos.length() {
    return false
  }
  let cargo = packer.cargos[cargo_index]
  for slot in packer.placed {
    // The stacking candidate sits exactly on the support face: a declared
    // clearance is lateral, so it must not lift cargo off what carries it.
    push_point(
      points,
      Point3::new(slot.box.min.x, slot.box.min.y, slot.box.max_z()),
      packer.envelope,
    )
    let gap = max_i(
      cargo.min_gap_mm,
      packer.cargos[slot.cargo_index].min_gap_mm,
    )
    if gap > 0 {
      push_point(
        points,
        Point3::new(slot.box.max_x() + gap, slot.box.min.y, slot.box.min.z),
        packer.envelope,
      )
      push_point(
        points,
        Point3::new(slot.box.min.x, slot.box.max_y() + gap, slot.box.min.z),
        packer.envelope,
      )
    }
  }
  let mut best : Candidate? = None
  for o in cargo.upright.allowed() {
    let od = cargo.dims.oriented(o)
    for p in points {
      let box = Aabb::at(p.x, p.y, p.z, od)
      if !box.fits_within(packer.envelope) {
        continue
      }
      if !packer.fits(cargo_index, box) {
        continue
      }
      let supports = packer.supports_of_box(box)
      let below : Array[Aabb] = []
      for s in supports {
        below.push(packer.placed[s].box)
      }
      let area = box.size.length * box.size.width
      let supported = if area <= 0 {
        0
      } else {
        (box.supported_area(below).to_int64() * 1000L / area.to_int64()).to_int()
      }
      let cand = {
        box,
        orientation: o,
        layer: packer.layer_for(supports),
        support_permille: supported,
      }
      best = match best {
        None => Some(cand)
        Some(current) =>
          if better(cand, current) {
            Some(cand)
          } else {
            Some(current)
          }
      }
    }
  }
  match best {
    Some(cand) => {
      packer.commit(cargo_index, cand)
      push_point(
        points,
        Point3::new(cand.box.max_x(), cand.box.min.y, cand.box.min.z),
        packer.envelope,
      )
      push_point(
        points,
        Point3::new(cand.box.min.x, cand.box.max_y(), cand.box.min.z),
        packer.envelope,
      )
      push_point(
        points,
        Point3::new(cand.box.min.x, cand.box.min.y, cand.box.max_z()),
        packer.envelope,
      )
      true
    }
    None => false
  }
}

///|
/// Place every cargo in `order`, then re-attempt the failures: each placement
/// adds new extreme points, so an item that had no room early in the run often
/// fits once the unit is fuller. `rounds` bounds the retry passes and the loop
/// stops as soon as a pass changes nothing.
fn pack_rounds(
  unit : LoadUnit,
  cargos : Array[Cargo],
  rules : StowRules,
  order : Array[Int32],
  rounds : Int32,
) -> LoadPlan {
  match blocked_plan(unit, cargos, rules) {
    Some(blocked) => return blocked
    None => ()
  }
  let packer = Packer::new(unit, cargos, rules)
  let points : Array[Point3] = [Point3::new(0, 0, 0)]
  let attempted : Array[Int32] = []
  let mut failed : Array[Int32] = []
  for cargo_index in order {
    if cargo_index < 0 || cargo_index >= cargos.length() {
      continue
    }
    let mut duplicate = false
    for i in attempted {
      if i == cargo_index {
        duplicate = true
      }
    }
    if duplicate {
      continue
    }
    attempted.push(cargo_index)
    if !place_one(packer, points, cargo_index) {
      failed.push(cargo_index)
    }
  }
  let mut round = 0
  while round < rounds && failed.length() > 0 {
    let next_failed : Array[Int32] = []
    for idx in failed {
      if !place_one(packer, points, idx) {
        next_failed.push(idx)
      }
    }
    if next_failed.length() == failed.length() {
      round = rounds
    } else {
      failed = next_failed
      round = round + 1
    }
  }
  let unplaced : Array[Unplaced] = []
  for idx in failed {
    unplaced.push({
      cargo_id: cargos[idx].id,
      reason: "no feasible position left in the unit",
    })
  }
  for i in 0..<cargos.length() {
    let mut seen = false
    for v in attempted {
      if v == i {
        seen = true
      }
    }
    if !seen {
      unplaced.push({
        cargo_id: cargos[i].id,
        reason: "cargo omitted from explicit packing order",
      })
    }
  }
  let placements = balance_load(
    unit,
    slots_to_placements(packer.placed, cargos),
    cargos,
  )
  let metrics = compute_metrics(unit, cargos, placements)
  let violations = verify(unit, cargos, placements, rules)
  {
    unit_id: unit.id,
    unit_kind: unit.kind,
    placements,
    unplaced,
    metrics,
    violations,
  }
}

///|
/// Pack every cargo into the unit in the given order. Items that cannot be
/// placed are reported with the reason, they are never silently dropped.
pub fn pack_ordered(
  unit : LoadUnit,
  cargos : Array[Cargo],
  rules : StowRules,
  order : Array[Int32],
) -> LoadPlan {
  pack_rounds(unit, cargos, rules, order, 0)
}

///|
/// Pack with the built in ordering (earliest stop, highest priority, heaviest,
/// largest, id).
pub fn pack(
  unit : LoadUnit,
  cargos : Array[Cargo],
  rules : StowRules,
) -> LoadPlan {
  pack_ordered(unit, cargos, rules, order_cargos(cargos))
}

///|
/// Which deterministic sort a run places cargo in. `Builtin` is the key that
/// `Cargo::sort_key` documents and that `pack` uses; the others trade a little
/// delivery order for a tighter fill, which is what `pack_best` explores.
#derive(Eq)
pub(all) enum OrderKey {
  Builtin
  VolumeDesc
  HeightDesc
  AreaDesc
  WeightDesc
  VolumeAsc
}

///|
pub fn OrderKey::label(self : OrderKey) -> String {
  match self {
    Builtin => "builtin"
    VolumeDesc => "volume-desc"
    HeightDesc => "height-desc"
    AreaDesc => "area-desc"
    WeightDesc => "weight-desc"
    VolumeAsc => "volume-asc"
  }
}

///|
pub fn OrderKey::all() -> Array[OrderKey] {
  [Builtin, VolumeDesc, HeightDesc, AreaDesc, WeightDesc, VolumeAsc]
}

///|
fn order_metric(cargo : Cargo, key : OrderKey) -> Int64 {
  match key {
    Builtin | VolumeDesc | VolumeAsc => cargo.dims.volume_mm3()
    HeightDesc => cargo.dims.height.to_int64()
    AreaDesc => cargo.dims.length.to_int64() * cargo.dims.width.to_int64()
    WeightDesc => cargo.weight_g.to_int64()
  }
}

///|
fn order_precedes(a : Cargo, b : Cargo, key : OrderKey) -> Bool {
  let av = order_metric(a, key)
  let bv = order_metric(b, key)
  if av != bv {
    return match key {
      VolumeAsc => av < bv
      _ => av > bv
    }
  }
  a.id < b.id
}

///|
fn sorted_indices(cargos : Array[Cargo], key : OrderKey) -> Array[Int32] {
  let idx : Array[Int32] = []
  for i in 0..<cargos.length() {
    idx.push(i)
  }
  let n = idx.length()
  let mut i = 1
  while i < n {
    let item = idx[i]
    let mut j = i - 1
    let mut done = false
    while j >= 0 && !done {
      if order_precedes(cargos[item], cargos[idx[j]], key) {
        idx[j + 1] = idx[j]
        j = j - 1
      } else {
        done = true
      }
    }
    idx[j + 1] = item
    i = i + 1
  }
  idx
}

///|
/// Cargo indices in the order `key` asks for. Ties fall back to the cargo id, so
/// the order is total and the packer stays deterministic whatever order the
/// caller handed the cargo in.
pub fn order_cargos_by(cargos : Array[Cargo], key : OrderKey) -> Array[Int32] {
  match key {
    Builtin => order_cargos(cargos)
    _ => sorted_indices(cargos, key)
  }
}

///|
/// Prefer the plan that places more pieces, because "how much of my freight
/// fits" is the question a planner asks first; on a tie prefer the plan that
/// loads more volume, then the one that stays lower. A strict order keeps the
/// choice of `pack_best` deterministic.
fn better_plan(a : LoadPlan, b : LoadPlan) -> Bool {
  if a.metrics.placed_count != b.metrics.placed_count {
    return a.metrics.placed_count > b.metrics.placed_count
  }
  if a.metrics.used_volume_mm3 != b.metrics.used_volume_mm3 {
    return a.metrics.used_volume_mm3 > b.metrics.used_volume_mm3
  }
  a.metrics.stack_height_mm < b.metrics.stack_height_mm
}

///|
/// Quality mode: run the heuristic once per `OrderKey`, give every run two
/// retry passes, and keep the plan that loads the most volume. It is slower than
/// `pack` on purpose and just as deterministic, so a replayed job prints the
/// same plan.
pub fn pack_best(
  unit : LoadUnit,
  cargos : Array[Cargo],
  rules : StowRules,
) -> LoadPlan {
  let mut best : LoadPlan? = None
  for key in OrderKey::all() {
    let plan = pack_rounds(unit, cargos, rules, order_cargos_by(cargos, key), 2)
    best = match best {
      None => Some(plan)
      Some(current) =>
        if better_plan(plan, current) {
          Some(plan)
        } else {
          Some(current)
        }
    }
  }
  match best {
    Some(plan) => plan
    None => pack(unit, cargos, rules)
  }
}

///|
/// Pack and only return a plan when every single cargo found a position.
pub fn pack_all(
  unit : LoadUnit,
  cargos : Array[Cargo],
  rules : StowRules,
) -> LoadPlan? {
  let plan = pack(unit, cargos, rules)
  if plan.unplaced.length() == 0 && is_clear(plan.violations) {
    Some(plan)
  } else {
    None
  }
}

///|
fn slots_to_placements(
  slots : Array[Slot],
  cargos : Array[Cargo],
) -> Array[Placement] {
  let out : Array[Placement] = []
  for s in slots {
    let cargo = cargos[s.cargo_index]
    out.push({
      cargo_id: cargo.id,
      cargo_index: s.cargo_index,
      orientation: s.orientation,
      box: s.box,
      stop: cargo.stop,
      layer: s.layer,
    })
  }
  out
}

///|
/// Sort placements by delivery stop then near-to-far from the door, which is the
/// order a loader works in and the order reports print.
pub fn sort_placements(placements : Array[Placement]) -> Array[Placement] {
  let out = placements.copy()
  let n = out.length()
  let mut i = 1
  while i < n {
    let item = out[i]
    let mut j = i - 1
    let mut done = false
    while j >= 0 && !done {
      let prev = out[j]
      let swap = prev.stop > item.stop ||
        (prev.stop == item.stop && prev.box.min.x > item.box.min.x)
      if swap {
        out[j + 1] = prev
        j = j - 1
      } else {
        done = true
      }
    }
    out[j + 1] = item
    i = i + 1
  }
  out
}
