///|
/// Shelf packing: cargo is arranged in horizontal layers, each layer filled row by
/// row from the door corner outwards. This is how a pallet or a truck is really
/// built (a loader cannot drop a box into a cavity), and it produces a plan whose
/// support graph is a clean stack of layers.
///
/// Layers are horizontal bands: every box in a band stands on the band below (or
/// on the pallet itself), and the band height is the tallest box in it.
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
  let mut z = 0
  let mut rounds = 0
  while z < envelope.height && rounds < 200 {
    rounds = rounds + 1
    let mut layer_height = 0
    // shelf state for this band
    let mut y = 0
    let mut x = 0
    let mut row_depth = 0
    let mut placed_in_layer = 0
    for idx in order {
      if planned[idx] {
        continue
      }
      let cargo = cargos[idx]
      let mut placed_here = false
      let mut attempts = 0
      while attempts < 6 && !placed_here {
        attempts = attempts + 1
        for o in cargo.upright.allowed() {
          let od = cargo.dims.oriented(o)
          if od.height > envelope.height - z {
            continue
          }
          if x + od.length > envelope.length {
            // open a new row
            continue
          }
          if y + od.width > envelope.width {
            continue
          }
          let box = Aabb::at(x, y, z, od)
          if packer.fits(idx, box) {
            packer.commit(idx, Candidate::{
              box,
              orientation: o,
              layer: 0,
              support_permille: 1000,
            })
            planned[idx] = true
            placed_here = true
            placed_in_layer = placed_in_layer + 1
            layer_height = max_i(layer_height, od.height)
            row_depth = max_i(row_depth, od.width)
            x = x + od.length
            break
          }
        }
        if !placed_here {
          // move to the next slot: next row, or next band
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
    if placed_in_layer == 0 {
      break
    }
    z = z + max_i(layer_height, 1)
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

///|
test "palletize: six cartons on a euro pallet" {
  let unit = LoadUnit::pallet_eur("P1")
  let cargos : Array[Cargo] = []
  for i in 0..<6 {
    cargos.push(
      Cargo::new("C" + i.to_string(), Dimensions::new(400, 300, 300), 8_000),
    )
  }
  let plan = palletize(unit, cargos, StowRules::default())
  assert_eq(plan.placements.length(), 6)
  assert_eq(plan.unplaced.length(), 0)
  assert_true(is_clear(plan.violations))
  assert_true(plan.metrics.stack_height_mm > 0)
}
