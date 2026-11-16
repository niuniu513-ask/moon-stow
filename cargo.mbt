///|
/// How much a cargo may be rotated. `Fixed` keeps the declared orientation,
/// `KeepUpright` allows the 90 degree turn on the floor, `Free` allows all six
/// axis aligned orientations.
pub(all) enum UprightPolicy {
  Fixed
  KeepUpright
  Free
} derive(Eq)

///|
pub fn UprightPolicy::allowed(self : UprightPolicy) -> Array[Orientation] {
  match self {
    Fixed => [LWH]
    KeepUpright => [LWH, WLH]
    Free => [LWH, WLH, LHW, HLW, WHL, HWL]
  }
}

///|
/// One piece of freight. Everything the packer and the verifier need is on this
/// record: geometry, mass, stacking limits, hazard class, delivery stop.
pub(all) struct Cargo {
  id : String
  dims : Dimensions
  weight_g : Int32
  upright : UprightPolicy
  stackable : Bool
  max_stack_layers : Int32
  max_top_load_g : Int32
  fragile : Bool
  hazard : Hazard
  stop : Int32
  group : String
  priority : Int32
  min_gap_mm : Int32
} derive(Eq)

///|
/// A plain carton: 600 x 400 x 400, 12 kg, upright, stackable in three layers.
pub fn Cargo::new(id : String, dims : Dimensions, weight_g : Int32) -> Cargo {
  {
    id,
    dims,
    weight_g,
    upright: KeepUpright,
    stackable: true,
    max_stack_layers: 3,
    max_top_load_g: 60_000,
    fragile: false,
    hazard: Hazard::none(),
    stop: 0,
    group: "",
    priority: 0,
    min_gap_mm: 0,
  }
}

///|
pub fn Cargo::max_height(self : Cargo) -> Int32 {
  let mut best = 0
  for o in self.upright.allowed() {
    best = max_i(best, self.dims.oriented(o).height)
  }
  best
}

///|
pub fn Cargo::with_stop(self : Cargo, stop : Int32) -> Cargo {
  { ..self, stop, }
}

///|
pub fn Cargo::with_hazard(self : Cargo, hazard : Hazard) -> Cargo {
  { ..self, hazard, }
}

///|
pub fn Cargo::with_upright(self : Cargo, upright : UprightPolicy) -> Cargo {
  { ..self, upright, }
}

///|
pub fn Cargo::with_stack_limit(
  self : Cargo,
  layers : Int32,
  top_load_g : Int32,
) -> Cargo {
  { ..self, max_stack_layers: layers, max_top_load_g: top_load_g, }
}

///|
pub fn Cargo::fragile_item(self : Cargo) -> Cargo {
  {
    ..self,
    fragile: true,
    stackable: false,
    max_stack_layers: 1,
    max_top_load_g: 0,
  }
}

///|
pub fn Cargo::with_priority(self : Cargo, priority : Int32) -> Cargo {
  { ..self, priority, }
}

///|
pub fn Cargo::with_group(self : Cargo, group : String) -> Cargo {
  { ..self, group, }
}

///|
pub fn Cargo::with_gap(self : Cargo, gap_mm : Int32) -> Cargo {
  { ..self, min_gap_mm: gap_mm, }
}

///|
/// Cargo that cannot carry anything is a stack of one and blocks any load above
/// it, which is exactly what `fragile_item` sets up.
pub fn Cargo::accepts_load_on_top(self : Cargo, weight_g : Int32) -> Bool {
  self.stackable && self.max_stack_layers > 1 && self.max_top_load_g >= weight_g
}

///|
/// Sort key used by every heuristic: earliest delivery stop first, then higher
/// priority, then heavier, then larger footprint, then id. A total order means
/// the packer is deterministic regardless of input order.
pub fn Cargo::sort_key(self : Cargo) -> String {
  let stop = self.stop.to_string()
  let priority = 1_000_000 - self.priority
  let weight = 10_000_000 - min_i(self.weight_g, 9_999_999)
  let volume = 1_000_000_000_000L -
    min64(self.dims.volume_mm3(), 999_999_999_999L)
  pad_left(stop, 4) +
  "|" +
  pad_left(priority.to_string(), 8) +
  "|" +
  pad_left(weight.to_string(), 8) +
  "|" +
  pad_left(volume.to_string(), 14) +
  "|" +
  self.id
}

///|
fn pad_left(text : String, width : Int32) -> String {
  let mut out = ""
  let mut i = text.length()
  while i < width {
    out = out + "0"
    i = i + 1
  }
  out + text
}

///|
test "cargo: defaults are safe" {
  let c = Cargo::new("A", Dimensions::new(600, 400, 400), 12_000)
  assert_eq(c.stop, 0)
  assert_true(c.stackable)
  assert_false(c.hazard.class.is_regulated())
  assert_eq(c.upright.allowed().length(), 2)
}

///|
test "cargo: fragile cargo refuses load" {
  let c = Cargo::new("A", Dimensions::new(600, 400, 400), 12_000).fragile_item()
  assert_false(c.accepts_load_on_top(1_000))
  assert_eq(c.max_stack_layers, 1)
}

///|
test "cargo: sort key prefers early stops" {
  let a = Cargo::new("A", Dimensions::new(100, 100, 100), 1_000).with_stop(1)
  let b = Cargo::new("B", Dimensions::new(100, 100, 100), 1_000).with_stop(2)
  assert_true(a.sort_key() < b.sort_key())
}

///|
pub extend UprightPolicy with Eq::{equal, not_equal}

///|
pub extend Cargo with Eq::{equal, not_equal}
