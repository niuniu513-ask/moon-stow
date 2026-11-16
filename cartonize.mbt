///|
/// A shippable carton from the warehouse catalogue. `cost_cents` is the landed
/// cost of the box plus the filler needed to protect the goods, which is what an
/// operator actually minimises; `inner` is the usable inside size.
pub(all) struct CartonSpec {
  id : String
  inner : Dimensions
  max_weight_g : Int32
  cost_cents : Int32
} derive(Eq)

///|
pub extend CartonSpec with Eq::{equal, not_equal}

///|
pub fn CartonSpec::new(
  id : String,
  inner : Dimensions,
  max_weight_g : Int32,
  cost_cents : Int32,
) -> CartonSpec {
  { id, inner, max_weight_g, cost_cents, }
}

///|
pub fn CartonSpec::as_unit(self : CartonSpec) -> LoadUnit {
  {
    id: self.id,
    kind: Container,
    dims: self.inner,
    max_payload_g: self.max_weight_g,
    tare_g: 0,
    floor_limit_g_per_m2: 0,
    axles: [],
    rear_door_at_origin: true,
    max_stack_height_mm: self.inner.height,
  }
}

///|
/// One chosen carton together with the placement of the goods inside it.
pub(all) struct CartonPick {
  carton : CartonSpec
  plan : LoadPlan
} derive(Eq)

///|
pub extend CartonPick with Eq::{equal, not_equal}

///|
pub(all) struct Cartonization {
  picks : Array[CartonPick]
  unpacked : Array[Unplaced]
  total_cost_cents : Int32
  total_inner_volume_mm3 : Int64
  goods_volume_mm3 : Int64
  void_fill_permille : Int32
} derive(Eq)

///|
pub extend Cartonization with Eq::{equal, not_equal}

///|
/// Volumetric weight used by parcel carriers (1 kg per 5 litres), in grams.
pub fn volumetric_weight_g(dims : Dimensions) -> Int32 {
  (dims.volume_mm3() / 5_000L).to_int()
}

///|
/// Chargeable weight of a carton: the larger of actual and volumetric weight.
pub fn chargeable_weight_g(spec : CartonSpec, goods_weight_g : Int32) -> Int32 {
  max_i(goods_weight_g, volumetric_weight_g(spec.inner))
}

///|
/// Choose cartons for a set of goods.
///
/// The rule is the one a pack station follows: for every catalogue carton, work
/// out how many of the remaining goods it can hold (largest goods first, because
/// they are the hard ones), take the carton that holds the most goods for the
/// least money, ship it, and repeat. Ties are broken by cost then by carton id so
/// the result is reproducible.
pub fn cartonize(
  catalog : Array[CartonSpec],
  goods : Array[Cargo],
  rules : StowRules,
) -> Cartonization {
  let picks : Array[CartonPick] = []
  let unpacked : Array[Unplaced] = []
  let remaining : Array[Int32] = []
  for i in 0..<goods.length() {
    remaining.push(i)
  }
  let order = order_by_volume(goods)
  let mut rounds = 0
  while remaining.length() > 0 && rounds < 200 {
    rounds = rounds + 1
    let mut best_carton : CartonSpec? = None
    let mut best_indices : Array[Int32] = []
    let mut best_plan : LoadPlan? = None
    for spec in catalog {
      let unit = spec.as_unit()
      // try to fit as many of the remaining goods as possible, largest first
      let mut count = 1
      let mut chosen_plan : LoadPlan? = None
      let mut chosen_indices : Array[Int32] = []
      while count <= remaining.length() {
        let subset : Array[Cargo] = []
        let subset_idx : Array[Int32] = []
        let mut taken = 0
        for idx in order {
          if taken >= count {
            break
          }
          let mut still_remaining = false
          for r in remaining {
            if r == idx {
              still_remaining = true
            }
          }
          if still_remaining {
            subset.push(goods[idx])
            subset_idx.push(idx)
            taken = taken + 1
          }
        }
        let plan = pack(unit, subset, rules)
        if plan.unplaced.length() == 0 && is_clear(plan.violations) {
          chosen_plan = Some(plan)
          chosen_indices = subset_idx
          count = count + 1
        } else {
          break
        }
      }
      match chosen_plan {
        Some(plan) => {
          let mut better = true
          match best_plan {
            None => ()
            Some(_) =>
              if chosen_indices.length() != best_indices.length() {
                better = chosen_indices.length() > best_indices.length()
              } else {
                match best_carton {
                  Some(bc) =>
                    if spec.cost_cents != bc.cost_cents {
                      better = spec.cost_cents < bc.cost_cents
                    } else {
                      better = spec.id < bc.id
                    }
                  None => better = true
                }
              }
          }
          if better && chosen_indices.length() > 0 {
            best_carton = Some(spec)
            best_indices = chosen_indices
            best_plan = Some(plan)
          }
        }
        None => ()
      }
    }
    match best_plan {
      Some(plan) => {
        picks.push({ carton: best_carton.unwrap(), plan, })
        let kept : Array[Int32] = []
        for r in remaining {
          let mut used = false
          for b in best_indices {
            if b == r {
              used = true
            }
          }
          if !used {
            kept.push(r)
          }
        }
        remaining.clear()
        for k in kept {
          remaining.push(k)
        }
      }
      None => {
        // nothing fits: report every remaining good as unpacked and stop
        for r in remaining {
          unpacked.push({
            cargo_id: goods[r].id,
            reason: "no carton in the catalogue fits this item",
          })
        }
        remaining.clear()
      }
    }
  }
  let mut cost = 0
  let mut inner_volume = 0L
  let mut goods_volume = 0L
  for pick in picks {
    cost = cost + pick.carton.cost_cents
    inner_volume = inner_volume + pick.carton.inner.volume_mm3()
    for p in pick.plan.placements {
      goods_volume = goods_volume + p.box.volume_mm3()
    }
  }
  let used = inner_volume - goods_volume
  {
    picks,
    unpacked,
    total_cost_cents: cost,
    total_inner_volume_mm3: inner_volume,
    goods_volume_mm3: goods_volume,
    void_fill_permille: ratio_permille(used, inner_volume),
  }
}

///|
fn order_by_volume(goods : Array[Cargo]) -> Array[Int32] {
  let idx : Array[Int32] = []
  for i in 0..<goods.length() {
    idx.push(i)
  }
  let keys : Array[String] = []
  for c in goods {
    let key = pad_left(
        (1_000_000_000_000L - min64(c.dims.volume_mm3(), 999_999_999_999L)).to_string(),
        14,
      ) +
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
test "cartonize: picks the smallest carton that holds one item" {
  let catalog = [
    CartonSpec::new("S", Dimensions::new(300, 250, 200), 5_000, 80),
    CartonSpec::new("M", Dimensions::new(400, 350, 300), 12_000, 120),
    CartonSpec::new("L", Dimensions::new(600, 500, 400), 25_000, 200),
  ]
  let goods = [Cargo::new("G1", Dimensions::new(250, 200, 150), 2_000)]
  let result = cartonize(catalog, goods, StowRules::default())
  assert_eq(result.picks.length(), 1)
  assert_eq(result.picks[0].carton.id, "S")
  assert_eq(result.unpacked.length(), 0)
  assert_eq(result.total_cost_cents, 80)
}
