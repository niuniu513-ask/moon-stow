///|
/// Severity of a rule violation. `Error` blocks a plan from being used, `Warning`
/// is something a planner must confirm, `Info` is advisory.
#derive(Eq)
pub(all) enum Severity {
  Error
  Warning
  Info
}

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
#derive(Eq)
pub(all) enum ViolationKind {
  InputInvalid
  CargoGap
  PlacementMetadata
  OutOfBounds
  Overlap
  InsufficientSupport
  StackLayersExceeded
  TopLoadExceeded
  PayloadExceeded
  FloorLimitExceeded
  AxleOverload
  Imbalance
  HazardInputInvalid
  HazardRuleUnknown
  HazardSameUnitForbidden
  HazardReviewRequired
  HazardPlanningOnly
  Overstow
  OrientationNotAllowed
  HeightExceeded
  UnknownCargo
  DuplicateCargo
  MissingCargo
}

///|
pub fn ViolationKind::label(self : ViolationKind) -> String {
  match self {
    InputInvalid => "invalid planning input"
    CargoGap => "declared cargo gap too small"
    PlacementMetadata =>
      "placement metadata does not match cargo or support graph"
    OutOfBounds => "outside the load unit envelope"
    Overlap => "solid overlap with another item"
    InsufficientSupport => "not enough support below"
    StackLayersExceeded => "stack layer limit exceeded"
    TopLoadExceeded => "load placed on top exceeds the limit"
    PayloadExceeded => "payload limit exceeded"
    FloorLimitExceeded => "floor point load limit exceeded"
    AxleOverload => "axle load limit exceeded"
    Imbalance => "centre of gravity outside the allowed band"
    HazardInputInvalid => "invalid dangerous goods input"
    HazardRuleUnknown => "dangerous goods relationship unknown"
    HazardSameUnitForbidden => "same load unit prohibited by supplied rule"
    HazardReviewRequired => "dangerous goods human review required"
    HazardPlanningOnly => "dangerous goods planning only"
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
#derive(Eq)
pub(all) struct Violation {
  kind : ViolationKind
  severity : Severity
  cargo_id : String
  other_id : String
  detail : String
}

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
#derive(Eq)
pub(all) struct StowRules {
  min_support_permille : Int32
  cog_margin_permille : Int32
  max_stack_layers : Int32
  hazard_pairs : Array[HazardPairRule]
  hazard_review : HazardReview?
  enforce_overstow : Bool
  enforce_axles : Bool
}

///|
/// Support ratio 70 percent, centre of gravity within 60 percent of the half
/// width, overstow and axle checks on, no global layer cap beyond the per cargo
/// limits.
pub fn StowRules::default() -> StowRules {
  {
    min_support_permille: 700,
    cog_margin_permille: 600,
    max_stack_layers: 0,
    hazard_pairs: [],
    hazard_review: None,
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
test "rules: default thresholds" {
  let r = StowRules::default()
  assert_eq(r.min_support_permille, 700)
  assert_eq(r.with_support(500).min_support_permille, 500)
}

///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend ViolationKind with Eq::{equal, not_equal}

///|
pub extend Violation with Eq::{equal, not_equal}

///|
pub extend StowRules with Eq::{equal, not_equal}
