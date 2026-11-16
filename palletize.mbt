///|
/// Shelf packing plus column stacking: the floor is laid out row by row from the
/// door corner, then every remaining box is stacked on a box that can carry its
/// whole base. This is how a pallet or a truck is really built -- a loader sets a
/// box down on another box, never into a cavity between two boxes -- and it keeps
/// the support graph simple enough to check by eye.
pub fn palletize(
  unit : LoadUnit,
  cargos : Array[Cargo],
  rules : StowRules,
) -> LoadPlan {
  let packer = Packer::new(unit, cargos, rules)
  let envelope = packer.envelope
  let order = order_by_footprint(cargos)
  let planned : Array[Bool] = []
  for _ in 0..<cargos.length() {
    planned.push(false)
  }
  // Floor band: one shelf layout at z = 0. Every position here is reachable by a
  // loader, so the floor is laid out first and never revisited.
  let mut y = 0
  let mut x = 0
  let mut row_depth = 0
  for idx in order {
    if planned[idx] {
      continue
    }
    let cargo = cargos[idx]
    let mut placed_here = false
    let mut attempts = 0
    while attempts < 8 && !placed_here {
      attempts = attempts + 1
      for o in cargo.upright.allowed() {
        let od = cargo.dims.oriented(o)
        if od.height > envelope.height {
          continue
        }
        if x + od.length > envelope.length {
          continue
        }
        if y + od.width > envelope.width {
          continue
        }
        let box = Aabb::at(x, y, 0, od)
        if packer.fits(idx, box) {
          packer.commit(idx, Candidate::{
            box,
            orientation: o,
            layer: 0,
            support_permille: 1000,
          })
          planned[idx] = true
          placed_here = true
          row_depth = max_i(row_depth, od.width)
          x = x + od.length
          break
        }
      }
      if !placed_here {
        // Next slot: open a new row, or give up on the floor.
        if x == 0 {
          y = y + max_i(row_depth, 1)
          row_depth = 0
          if y >= envelope.width {
            break
          }
        } else {
          x = 0
        }
      }
    }
  }
  // Columns: for every box still standing on the floor, put one box on top of it
  // whenever the base fits and the rules allow it. One box per column per round,
  // so a column grows bottom-up and each step has full support.
  let mut rounds = 0
  let mut progress = true
  while progress && rounds < 400 {
    rounds = rounds + 1
    progress = false
    let snapshot : Array[Int32] = []
    for s in 0..<packer.placed.length() {
      snapshot.push(s)
    }
    for s in snapshot {
      let base = packer.placed[s]
      if base.load_on_top_g > 0 {
        continue
      }
      for idx in order {
        if planned[idx] {
          continue
        }
        let cargo = cargos[idx]
        let mut done = false
        for o in cargo.upright.allowed() {
          if done {
            continue
          }
          let od = cargo.dims.oriented(o)
          if od.length <= base.box.size.length &&
            od.width <= base.box.size.width {
            let box = Aabb::at(
              base.box.min.x,
              base.box.min.y,
              base.box.max_z(),
              od,
            )
            if packer.fits(idx, box) {
              packer.commit(idx, Candidate::{
                box,
                orientation: o,
                layer: 0,
                support_permille: 1000,
              })
              planned[idx] = true
              done = true
              progress = true
            }
          }
        }
        if done {
          break
        }
      }
    }
  }
  let placements = balance_load(
    unit,
    slots_to_placements(packer.placed, cargos),
    cargos,
  )
  let unplaced : Array[Unplaced] = []
  for i in 0..<cargos.length() {
    if !planned[i] {
      unplaced.push({
        cargo_id: cargos[i].id,
        reason: "does not fit in a shelf layer",
      })
    }
  }
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
/// Order for shelf packing: largest footprint first, then tallest, then id, so a
/// layer is filled with the boxes that set the layer height and the small ones
/// fill the gaps afterwards.
pub fn order_by_footprint(cargos : Array[Cargo]) -> Array[Int32] {
  let idx : Array[Int32] = []
  for i in 0..<cargos.length() {
    idx.push(i)
  }
  let keys : Array[String] = []
  for c in cargos {
    let area = floor_area_mm2(c.dims)
    let height = c.dims.height
    let key = pad_left(
        (1_000_000_000_000L - min64(area, 999_999_999_999L)).to_string(),
        14,
      ) +
      "|" +
      pad_left((100_000 - min_i(height, 99_999)).to_string(), 6) +
      "|" +
      c.id
    keys.push(key)
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
