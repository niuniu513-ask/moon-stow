///|
/// Internal packing state: one slot is a committed box plus the load it carries.
struct Slot {
  cargo_index : Int32
  box : Aabb
  orientation : Orientation
  mut layer : Int32
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
  mut placed : Array[Slot]
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
/// Slot indices ordered by bottom face, lowest first. Supports always sit lower
/// than what they carry, so this order lets one pass stamp every layer without
/// recursion.
fn Packer::by_bottom(self : Packer) -> Array[Int32] {
  let n = self.placed.length()
  let order : Array[Int32] = []
  for i in 0..<n {
    order.push(i)
  }
  let mut i = 1
  while i < n {
    let item = order[i]
    let mut j = i - 1
    let mut done = false
    while j >= 0 && !done {
      if self.placed[order[j]].box.min.z > self.placed[item].box.min.z {
        order[j + 1] = order[j]
        j = j - 1
      } else {
        done = true
      }
    }
    order[j + 1] = item
    i = i + 1
  }
  order
}

///|
/// Re-derive every layer from the support graph as it stands now. A later
/// placement can slide under an earlier box and give it a support edge it did
/// not have when it was committed, which lifts that box and everything above it;
/// the stamped layer is therefore only valid until the next commit, and the plan
/// is only auditable once this has been run after the last one.
fn Packer::restamp_layers(self : Packer) -> Unit {
  let n = self.placed.length()
  for index in self.by_bottom() {
    let box = self.placed[index].box
    let mut deepest = 0
    for k in 0..<n {
      if k != index &&
        self.placed[k].box.max_z() == box.min.z &&
        self.placed[k].box.footprint_overlap(box) > 0 {
        deepest = max_i(deepest, self.placed[k].layer)
      }
    }
    self.placed[index].layer = if deepest == 0 { 1 } else { deepest + 1 }
  }
}

///|
/// Highest layer each slot may reach: its own ceiling, the global cap, and the
/// ceiling of everything that carries it. The verifier rejects a column that is
/// taller than any ancestor allows, so the ceiling has to travel upwards with
/// the rest of the stack.
fn Packer::layer_ceiling(self : Packer) -> Array[Int32] {
  let n = self.placed.length()
  let ceilings : Array[Int32] = []
  for i in 0..<n {
    ceilings.push(self.cargos[self.placed[i].cargo_index].max_stack_layers)
  }
  for index in self.by_bottom() {
    let box = self.placed[index].box
    let mut ceiling = ceilings[index]
    if self.rules.max_stack_layers > 0 && self.rules.max_stack_layers < ceiling {
      ceiling = self.rules.max_stack_layers
    }
    for k in 0..<n {
      if k != index &&
        self.placed[k].box.max_z() == box.min.z &&
        self.placed[k].box.footprint_overlap(box) > 0 &&
        ceilings[k] < ceiling {
        ceiling = ceilings[k]
      }
    }
    ceilings[index] = ceiling
  }
  ceilings
}

///|
/// Rebuild the carried load of every slot from the support graph, which is what
/// the top load rules are checked against.
fn Packer::refresh_loads(self : Packer) -> Unit {
  for i in 0..<self.placed.length() {
    self.placed[i].load_on_top_g = 0
  }
  for i in 0..<self.placed.length() {
    let weight = self.cargos[self.placed[i].cargo_index].weight_g
    for s in self.ancestors(self.supports_of_box(self.placed[i].box)) {
      self.placed[s].load_on_top_g = self.placed[s].load_on_top_g + weight
    }
  }
}

///|
/// Drop the placements that the final support graph no longer allows. Removing
/// the topmost offender first is what keeps this sound: any box above an
/// over-tall one is over-tall itself and sits higher, so a column is always
/// shortened from the top and what stays below keeps every support it had.
fn Packer::prune_over_tall(self : Packer) -> Array[Int32] {
  let removed : Array[Int32] = []
  let limit = self.placed.length() + 1
  let mut steps = 0
  while steps < limit {
    steps = steps + 1
    self.restamp_layers()
    let ceilings = self.layer_ceiling()
    let mut victim = -1
    let mut victim_z = -1
    for i in 0..<self.placed.length() {
      if self.placed[i].layer > ceilings[i] &&
        self.placed[i].box.min.z > victim_z {
        victim_z = self.placed[i].box.min.z
        victim = i
      }
    }
    if victim < 0 {
      break
    }
    removed.push(self.placed[victim].cargo_index)
    let kept : Array[Slot] = []
    for i in 0..<self.placed.length() {
      if i != victim {
        kept.push(self.placed[i])
      }
    }
    self.placed = kept
    self.refresh_loads()
  }
  removed
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
fn pack_into(
  packer : Packer,
  points : Array[Point3],
  order : Array[Int32],
  rounds : Int32,
) -> (Array[Int32], Array[Int32]) {
  let attempted : Array[Int32] = []
  let mut failed : Array[Int32] = []
  for cargo_index in order {
    if cargo_index < 0 || cargo_index >= packer.cargos.length() {
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
  // The retry passes are not the last word on the stack: they can also add the
  // support edge that lifts an earlier box past a ceiling, so the plan is
  // re-derived and repaired before it is handed out.
  let capped : Array[Int32] = []
  for idx in packer.prune_over_tall() {
    capped.push(idx)
  }
  // A box that lost its column can very often go somewhere else, and it is
  // cheaper to try than to explain why it stayed behind.
  let retry : Array[Int32] = []
  for idx in capped {
    if !place_one(packer, points, idx) {
      retry.push(idx)
    }
  }
  for idx in packer.prune_over_tall() {
    retry.push(idx)
  }
  (failed, retry)
}

///|
/// Place every cargo in `order` into the unit, one pass plus the retry passes
/// that `pack_into` performs, and turn the result into a plan: unplaced cargo is
/// reported with its reason, the load is balanced, and the plan is audited by
/// the same verifier a caller would use.
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
  let (failed, capped) = pack_into(packer, points, order, rounds)
  let unplaced : Array[Unplaced] = []
  for idx in failed {
    unplaced.push({
      cargo_id: cargos[idx].id,
      reason: "no feasible position left in the unit",
    })
  }
  for idx in capped {
    unplaced.push({
      cargo_id: cargos[idx].id,
      reason: "column too tall once the final support graph was re-checked",
    })
  }
  for i in 0..<cargos.length() {
    let mut seen = false
    for v in order {
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
/// Distinct delivery stops of a manifest, in unload order.
fn distinct_stops(cargos : Array[Cargo]) -> Array[Int32] {
  let out : Array[Int32] = []
  for c in cargos {
    let mut seen = false
    for s in out {
      if s == c.stop {
        seen = true
      }
    }
    if !seen {
      out.push(c.stop)
    }
  }
  let n = out.length()
  let mut i = 1
  while i < n {
    let item = out[i]
    let mut j = i - 1
    while j >= 0 && out[j] > item {
      out[j + 1] = out[j]
      j = j - 1
    }
    out[j + 1] = item
    i = i + 1
  }
  out
}

///|
/// The cargo of one order that belongs to one delivery stop, order preserved.
fn order_for_stop(
  cargos : Array[Cargo],
  order : Array[Int32],
  stop : Int32,
) -> Array[Int32] {
  let out : Array[Int32] = []
  for i in order {
    if i >= 0 && i < cargos.length() && cargos[i].stop == stop {
      out.push(i)
    }
  }
  out
}

///|
/// The longest single item of a stop group along the loading axis, taking the
/// best orientation each item allows. A section shorter than this cannot hold
/// the group at all, so it is the floor of every section length.
fn group_min_length(cargos : Array[Cargo], group : Array[Int32]) -> Int32 {
  let mut need = 0
  for i in group {
    let cargo = cargos[i]
    let mut shortest = 0
    let mut first = true
    for o in cargo.upright.allowed() {
      let extent = cargo.dims.oriented(o).length
      if first || extent < shortest {
        shortest = extent
        first = false
      }
    }
    need = max_i(need, shortest)
  }
  need
}

///|
fn group_volume(cargos : Array[Cargo], group : Array[Int32]) -> Int64 {
  let mut total = 0L
  for i in group {
    total = total + cargos[i].dims.volume_mm3()
  }
  total
}

///|
/// Split the floor length between the delivery stops. Every stop first gets
/// enough room for its longest item, then the rest is shared in proportion to
/// volume, which keeps the fill ratio of every section the same. Rounding
/// leftovers go to the section closest to the door.
fn band_lengths(
  total : Int32,
  mins : Array[Int32],
  vols : Array[Int64],
) -> Array[Int32] {
  let n = mins.length()
  let out : Array[Int32] = []
  if n == 0 {
    return out
  }
  let mut sum_min = 0
  let mut sum_vol = 0L
  for i in 0..<n {
    sum_min = sum_min + mins[i]
    sum_vol = sum_vol + vols[i]
  }
  if total <= 0 {
    for _ in 0..<n {
      out.push(0)
    }
    return out
  }
  if sum_min >= total {
    // The minimums alone do not fit: share what there is in the same ratio, so
    // every section is short and the packer reports the overflow honestly.
    let mut left = total
    for i in 0..<n {
      let share = if i == n - 1 {
        left
      } else {
        (total.to_int64() * mins[i].to_int64() / sum_min.to_int64()).to_int()
      }
      let take = if share > left { left } else { share }
      out.push(take)
      left = left - take
    }
    return out
  }
  let remaining = total - sum_min
  let mut used = 0
  for i in 0..<n {
    let extra = if sum_vol <= 0L {
      remaining / n
    } else {
      (remaining.to_int64() * vols[i] / sum_vol).to_int()
    }
    let band = mins[i] + extra
    out.push(band)
    used = used + band
  }
  let slack = total - used
  if slack > 0 {
    out[0] = out[0] + slack
  }
  out
}

///|
/// Quality mode for a multi-stop manifest: give every delivery stop its own
/// longitudinal section, pack the sections one at a time and keep them in
/// unload order, so nothing of a later stop can end up in front of an earlier
/// one. The published `pack_best` interleaves stops and then rejects the boxes
/// the overstow rule blocks; on a 40 foot unit with three stops that costs about
/// a quarter of the manifest, which is the gap this entry point closes.
///
/// Section lengths come from the volume of each stop, with a floor of its
/// longest item, so a heavy and a light stop both get usable space. Each section
/// is a load unit of its own: it is packed with three orderings and two retry
/// passes, then the sections are concatenated, balanced and audited against the
/// real unit. The result is deterministic and passes the same verifier as every
/// other plan.
pub fn pack_stops(
  unit : LoadUnit,
  cargos : Array[Cargo],
  rules : StowRules,
) -> LoadPlan {
  match blocked_plan(unit, cargos, rules) {
    Some(blocked) => return blocked
    None => ()
  }
  let stops = distinct_stops(cargos)
  if stops.length() <= 1 {
    return pack_best(unit, cargos, rules)
  }
  let env = unit.envelope()
  let base = order_cargos(cargos)
  let groups : Array[Array[Int32]] = []
  let mins : Array[Int32] = []
  let vols : Array[Int64] = []
  for s in stops {
    let group = order_for_stop(cargos, base, s)
    groups.push(group)
    mins.push(group_min_length(cargos, group))
    vols.push(group_volume(cargos, group))
  }
  // A declared clearance is lateral, so two boxes that touch at a section
  // boundary would break it. Reserve the widest declared clearance between
  // neighbouring sections.
  let mut widest_gap = 0
  for c in cargos {
    widest_gap = max_i(widest_gap, c.min_gap_mm)
  }
  let mut min_total = 0
  for m in mins {
    min_total = min_total + m
  }
  let mut gap = widest_gap
  let mut usable = env.length - gap * (stops.length() - 1)
  if usable < min_total {
    // Not enough length to separate the stops and still let each one hold its
    // longest box. Sections that touch break a declared clearance at the
    // boundary, so the split stays a candidate only: the audit at the end
    // throws it away unless it comes out clean.
    gap = 0
    usable = env.length
  }
  let lengths = band_lengths(usable, mins, vols)
  let offsets : Array[Int32] = []
  if unit.rear_door_at_origin {
    let mut cursor = 0
    for i in 0..<lengths.length() {
      offsets.push(cursor)
      cursor = cursor + lengths[i] + gap
    }
  } else {
    let mut cursor = env.length
    for i in 0..<lengths.length() {
      let start = cursor - lengths[i]
      offsets.push(if start < 0 { 0 } else { start })
      cursor = start - gap
    }
  }
  let keys : Array[OrderKey] = [Builtin, VolumeDesc, AreaDesc]
  let merged : Array[Placement] = []
  for g in 0..<groups.length() {
    let length = lengths[g]
    if length <= 0 {
      continue
    }
    let section = LoadUnit::{
      ..unit,
      dims: Dimensions::new(length, env.width, env.height),
      max_payload_g: 0,
      axles: [],
    }
    // Payload is the one limit a section cannot judge: it only sees the cargo of
    // its own stop, so it is audited once on the whole plan instead. The deck
    // limits (floor pressure, stack height) belong to the unit and stay on.
    let mut best : Array[Slot] = []
    for key in keys {
      let packer = Packer::new(section, cargos, rules)
      let points : Array[Point3] = [Point3::new(0, 0, 0)]
      let order = order_for_stop(cargos, order_cargos_by(cargos, key), stops[g])
      let _ = pack_into(packer, points, order, 2)
      if packer.placed.length() > best.length() {
        best = packer.placed.copy()
      }
    }
    for slot in best {
      let cargo = cargos[slot.cargo_index]
      merged.push({
        cargo_id: cargo.id,
        cargo_index: slot.cargo_index,
        orientation: slot.orientation,
        box: Aabb::at(
          slot.box.min.x + offsets[g],
          slot.box.min.y,
          slot.box.min.z,
          slot.box.size,
        ),
        stop: cargo.stop,
        layer: slot.layer,
      })
    }
  }
  // Sections are packed on their own, so their support graphs are only
  // consistent one at a time: stamp and repair the merged plan as a whole.
  let placements = repair_layers(
    cargos,
    balance_load(unit, merged, cargos),
    rules,
  )
  let unplaced : Array[Unplaced] = []
  for c in cargos {
    let mut seen = false
    for p in placements {
      if p.cargo_id == c.id {
        seen = true
      }
    }
    if !seen {
      unplaced.push({
        cargo_id: c.id,
        reason: "no feasible position left in its delivery section",
      })
    }
  }
  let metrics = compute_metrics(unit, cargos, placements)
  let violations = verify(unit, cargos, placements, rules)
  let sectioned : LoadPlan = {
    unit_id: unit.id,
    unit_kind: unit.kind,
    placements,
    unplaced,
    metrics,
    violations,
  }
  // A section can be too narrow to pack well, which happens on a pallet deck
  // long before it happens in a container. Run the interleaved mode as well and
  // keep the better plan, so this entry point never loses ground on the one it
  // replaces.
  let interleaved = pack_best(unit, cargos, rules)
  // A clean plan always beats a fuller one: a section boundary that cannot keep
  // a declared clearance must lose to the interleaved plan, and only then does
  // the piece count decide.
  let sectioned_bad = count_violations(sectioned, MissingCargo)
  let interleaved_bad = count_violations(interleaved, MissingCargo)
  if sectioned_bad > interleaved_bad {
    interleaved
  } else if better_plan(sectioned, interleaved) {
    sectioned
  } else {
    interleaved
  }
}

///|
/// How many findings of any kind other than `except` a plan carries.
fn count_violations(plan : LoadPlan, except : ViolationKind) -> Int32 {
  let mut n = 0
  for v in plan.violations {
    if v.kind != except {
      n = n + 1
    }
  }
  n
}

///|
/// Placement indices ordered by bottom face, lowest first.
fn placements_by_bottom(placements : Array[Placement]) -> Array[Int32] {
  let n = placements.length()
  let order : Array[Int32] = []
  for i in 0..<n {
    order.push(i)
  }
  let mut i = 1
  while i < n {
    let item = order[i]
    let mut j = i - 1
    let mut done = false
    while j >= 0 && !done {
      if placements[order[j]].box.min.z > placements[item].box.min.z {
        order[j + 1] = order[j]
        j = j - 1
      } else {
        done = true
      }
    }
    order[j + 1] = item
    i = i + 1
  }
  order
}

///|
/// Re-derive every layer of a finished plan from its own support graph and drop
/// the placements that the graph does not allow any more, highest box first.
/// Removing the top of a column is what keeps the repair sound: a box above an
/// over-tall one is over-tall itself and sits higher, so the survivors keep every
/// support they had, and the plan that comes out is one the verifier agrees with.
fn repair_layers(
  cargos : Array[Cargo],
  placements : Array[Placement],
  rules : StowRules,
) -> Array[Placement] {
  let mut current = placements
  let limit = current.length() + 1
  let mut steps = 0
  while steps < limit {
    steps = steps + 1
    let layers = compute_layers(current)
    let ceilings : Array[Int32] = []
    for i in 0..<current.length() {
      let own = cargos[current[i].cargo_index].max_stack_layers
      ceilings.push(
        if rules.max_stack_layers > 0 && rules.max_stack_layers < own {
          rules.max_stack_layers
        } else {
          own
        },
      )
    }
    for index in placements_by_bottom(current) {
      let mut ceiling = ceilings[index]
      for s in supports_of(current, index) {
        if ceilings[s] < ceiling {
          ceiling = ceilings[s]
        }
      }
      ceilings[index] = ceiling
    }
    let mut victim = -1
    let mut victim_z = -1
    for i in 0..<current.length() {
      if layers[i] > ceilings[i] && current[i].box.min.z > victim_z {
        victim_z = current[i].box.min.z
        victim = i
      }
    }
    if victim < 0 {
      let stamped : Array[Placement] = []
      for i in 0..<current.length() {
        stamped.push({ ..current[i], layer: layers[i], })
      }
      return stamped
    }
    let kept : Array[Placement] = []
    for i in 0..<current.length() {
      if i != victim {
        kept.push(current[i])
      }
    }
    current = kept
  }
  current
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
