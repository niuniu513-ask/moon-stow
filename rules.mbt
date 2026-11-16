///|
/// Severity of a rule violation. `Error` blocks a plan from being used, `Warning`
/// is something a planner must confirm, `Info` is advisory.
pub(all) enum Severity {
  Error
  Warning
  Info
} derive(Eq)

///|
pub fn Severity::label(self : Severity) -> String {
  match self {
    Error => "error"
    Warning => "warning"
    Info => "info"
  }
}

///|
/// Every way a loading plan can be wrong. The list is deliberately flat: each
/// value maps to one check in `verify`, so a violation is always traceable to a
/// single rule instead of a paragraph of prose.
pub(all) enum ViolationKind {
  OutOfBounds
  Overlap
  InsufficientSupport
  StackLayersExceeded
  TopLoadExceeded
  PayloadExceeded
  FloorLimitExceeded
  AxleOverload
  Imbalance
  HazardClearance
  Overstow
  OrientationNotAllowed
  HeightExceeded
  UnknownCargo
  DuplicateCargo
  MissingCargo
} derive(Eq)

///|
pub fn ViolationKind::label(self : ViolationKind) -> String {
  match self {
    OutOfBounds => "outside the load unit envelope"
    Overlap => "solid overlap with another item"
    InsufficientSupport => "not enough support below"
    StackLayersExceeded => "stack layer limit exceeded"
    TopLoadExceeded => "load placed on top exceeds the limit"
    PayloadExceeded => "payload limit exceeded"
    FloorLimitExceeded => "floor point load limit exceeded"
    AxleOverload => "axle load limit exceeded"
    Imbalance => "centre of gravity outside the allowed band"
    HazardClearance => "dangerous goods clearance too small"
    Overstow => "later delivery blocks an earlier one"
    OrientationNotAllowed => "orientation not allowed for this cargo"
    HeightExceeded => "item exceeds the usable stacking height"
    UnknownCargo => "placement refers to unknown cargo"
    DuplicateCargo => "cargo placed more than once"
    MissingCargo => "cargo from the input has no placement"
  }
}

///|
/// A single finding, ready to print or to hand to a UI.
pub(all) struct Violation {
  kind : ViolationKind
  severity : Severity
  cargo_id : String
  other_id : String
  detail : String
} derive(Eq)

///|
pub fn Violation::new(
  kind : ViolationKind,
  severity : Severity,
  cargo_id : String,
  other_id : String,
  detail : String,
) -> Violation {
  { kind, severity, cargo_id, other_id, detail, }
}

///|
/// Thresholds and switches for verification. Defaults are the ones validated by
/// the shipped scenarios; a customer can tighten them without touching code.
pub(all) struct StowRules {
  min_support_permille : Int32
  cog_margin_permille : Int32
  max_stack_layers : Int32
  hazard_clearances : Array[Int32]
  enforce_overstow : Bool
  enforce_axles : Bool
} derive(Eq)

///|
/// Support ratio 70 percent, centre of gravity within 60 percent of the half
/// width, overstow and axle checks on, no global layer cap beyond the per cargo
/// limits.
pub fn StowRules::default() -> StowRules {
  {
    min_support_permille: 700,
    cog_margin_permille: 600,
    max_stack_layers: 0,
    hazard_clearances: [],
    enforce_overstow: true,
    enforce_axles: true,
  }
}

///|
pub fn StowRules::with_support(self : StowRules, permille : Int32) -> StowRules {
  { ..self, min_support_permille: permille, }
}

///|
pub fn StowRules::with_cog_margin(
  self : StowRules,
  permille : Int32,
) -> StowRules {
  { ..self, cog_margin_permille: permille, }
}

///|
pub fn StowRules::with_layer_cap(self : StowRules, layers : Int32) -> StowRules {
  { ..self, max_stack_layers: layers, }
}

///|
pub fn StowRules::allow_max_separation(self : StowRules) -> StowRules {
  { ..self, hazard_clearances: [0, 3_000, 6_000, 12_000, 24_000], }
}

///|
/// Clearance required for a segregation level under this rule set. An empty
/// override table falls back to the built in IMG-shaped ladder.
pub fn StowRules::clearance(self : StowRules, level : Int32) -> Int32 {
  if self.hazard_clearances.length() > level && level >= 0 {
    self.hazard_clearances[level]
  } else {
    clearance_for_level(level)
  }
}

///|
test "rules: default thresholds" {
  let r = StowRules::default()
  assert_eq(r.min_support_permille, 700)
  assert_eq(r.clearance(2), 6_000)
  assert_eq(r.with_support(500).min_support_permille, 500)
}

///|
test "rules: custom clearance table wins" {
  let r = StowRules::default().allow_max_separation()
  assert_eq(r.clearance(1), 3_000)
  assert_eq(r.clearance(4), 24_000)
}

///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend ViolationKind with Eq::{equal, not_equal}

///|
pub extend Violation with Eq::{equal, not_equal}

///|
pub extend StowRules with Eq::{equal, not_equal}
