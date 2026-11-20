///|
/// Dangerous-goods classes, numbered as in the UN Model Regulations / IMDG code.
/// `None` is an explicit non-dangerous declaration, not evidence of compatibility.
#derive(Eq)
pub(all) enum HazardClass {
  None
  Explosive
  GasFlammable
  GasNonFlammable
  GasToxic
  FlammableLiquid
  FlammableSolid
  SpontaneouslyCombustible
  DangerousWhenWet
  Oxidizer
  OrganicPeroxide
  Toxic
  Infectious
  Radioactive
  Corrosive
  Miscellaneous
}

///|
pub fn HazardClass::index(self : HazardClass) -> Int32 {
  match self {
    None => 0
    Explosive => 1
    GasFlammable => 2
    GasNonFlammable => 3
    GasToxic => 4
    FlammableLiquid => 5
    FlammableSolid => 6
    SpontaneouslyCombustible => 7
    DangerousWhenWet => 8
    Oxidizer => 9
    OrganicPeroxide => 10
    Toxic => 11
    Infectious => 12
    Radioactive => 13
    Corrosive => 14
    Miscellaneous => 15
  }
}

///|
/// The UN class code printed on the orange plate: "3", "2.1", "6.2" and so on.
pub fn HazardClass::code(self : HazardClass) -> String {
  match self {
    None => "-"
    Explosive => "1"
    GasFlammable => "2.1"
    GasNonFlammable => "2.2"
    GasToxic => "2.3"
    FlammableLiquid => "3"
    FlammableSolid => "4.1"
    SpontaneouslyCombustible => "4.2"
    DangerousWhenWet => "4.3"
    Oxidizer => "5.1"
    OrganicPeroxide => "5.2"
    Toxic => "6.1"
    Infectious => "6.2"
    Radioactive => "7"
    Corrosive => "8"
    Miscellaneous => "9"
  }
}

///|
pub fn HazardClass::is_regulated(self : HazardClass) -> Bool {
  match self {
    None => false
    _ => true
  }
}

///|
pub fn HazardClass::parse(text : String) -> HazardClass? {
  match text.trim() {
    "1" => Some(Explosive)
    "2.1" => Some(GasFlammable)
    "2.2" => Some(GasNonFlammable)
    "2.3" => Some(GasToxic)
    "3" => Some(FlammableLiquid)
    "4.1" => Some(FlammableSolid)
    "4.2" => Some(SpontaneouslyCombustible)
    "4.3" => Some(DangerousWhenWet)
    "5.1" => Some(Oxidizer)
    "5.2" => Some(OrganicPeroxide)
    "6.1" => Some(Toxic)
    "6.2" => Some(Infectious)
    "7" => Some(Radioactive)
    "8" => Some(Corrosive)
    "9" => Some(Miscellaneous)
    _ => None
  }
}

///|
/// Packing group as used for liquids: I is the most dangerous.
#derive(Eq)
pub(all) enum PackingGroup {
  NotApplicable
  I
  II
  III
}

///|
/// A declared dangerous good. `None` is the default for ordinary freight, so a
/// plan that never mentions hazards still carries a well defined value.
#derive(Eq)
pub(all) struct Hazard {
  class : HazardClass
  un_number : String
  packing_group : PackingGroup
  declaration_ref : String
}

///|
pub fn Hazard::none() -> Hazard {
  {
    class: None,
    un_number: "",
    packing_group: NotApplicable,
    declaration_ref: "",
  }
}

///|
pub fn Hazard::new(
  class : HazardClass,
  un_number : String,
  group : PackingGroup,
) -> Hazard {
  { class, un_number, packing_group: group, declaration_ref: "", }
}

///|
/// Reference to the exact SDS/declaration revision, including composition,
/// concentration, subsidiary hazards, packaging and quantity. Contents are
/// reviewed outside this library; a nonempty reference is not authentication.
pub fn Hazard::with_declaration(self : Hazard, reference : String) -> Hazard {
  { ..self, declaration_ref: reference, }
}

///|
/// Lexical validation only. It does not identify the substance from its UN code.
pub fn Hazard::is_valid(self : Hazard) -> Bool {
  if !self.class.is_regulated() {
    return self.un_number == "" &&
      self.packing_group == NotApplicable &&
      self.declaration_ref == ""
  }
  let text = self.un_number
  let start = if text.length() == 6 && text[0:2].to_owned() == "UN" {
    2
  } else {
    0
  }
  if text.length() - start != 4 {
    return false
  }
  for i in start..<text.length() {
    let ch = text[i:i + 1].to_owned()
    if ch < "0" || ch > "9" {
      return false
    }
  }
  text[start:text.length()].to_owned() != "0000"
}

///|
/// An operator-supplied relationship for exact declarations, never an IMDG table.
#derive(Eq)
pub(all) enum HazardRelation {
  ProhibitSameUnit
  ReviewRequired
}

///|
#derive(Eq)
pub(all) struct HazardPairRule {
  a : Hazard
  b : Hazard
  relation : HazardRelation
  rule_id : String
  source : String
}

///|
/// Evidence for a whole manifest and load unit. The constructor copies mutable
/// arrays so subsequent caller edits invalidate, rather than rewrite, the review.
/// This is a planning record, not a digital signature or transport permission.
#derive(Eq)
pub struct HazardReview {
  unit : LoadUnit
  cargos : Array[Cargo]
  pairs : Array[HazardPairRule]
  record_id : String
  reviewer : String
  evidence : String
}

///|
pub fn HazardReview::new(
  unit : LoadUnit,
  cargos : Array[Cargo],
  pairs : Array[HazardPairRule],
  record_id : String,
  reviewer : String,
  evidence : String,
) -> HazardReview {
  {
    unit: { ..unit, axles: unit.axles.copy(), },
    cargos: cargos.copy(),
    pairs: pairs.copy(),
    record_id,
    reviewer,
    evidence,
  }
}

///|
fn HazardReview::matches(
  self : HazardReview,
  unit : LoadUnit,
  cargos : Array[Cargo],
  pairs : Array[HazardPairRule],
) -> Bool {
  self.unit == unit &&
  self.cargos == cargos &&
  self.pairs == pairs &&
  self.record_id.trim().length() > 0 &&
  self.reviewer.trim().length() > 0 &&
  self.evidence.trim().length() > 0
}

///|
/// Checks the entire submitted manifest, including unplaced goods. Unknown pairs,
/// missing/stale reviews and explicit prohibitions block the whole job. A split
/// requires a new manifest and a new review, never a side effect of box spacing.
pub fn assess_hazards(
  unit : LoadUnit,
  cargos : Array[Cargo],
  rules : StowRules,
) -> Array[Violation] {
  let out : Array[Violation] = []
  let mut regulated = false
  for i in 0..<cargos.length() {
    let c = cargos[i]
    if !c.hazard.is_valid() {
      out.push(
        Violation::new(
          HazardInputInvalid,
          Error,
          c.id,
          "",
          "malformed dangerous goods declaration; no substance lookup performed",
        ),
      )
    }
    if c.hazard.class.is_regulated() {
      regulated = true
      if c.hazard.declaration_ref.trim().length() == 0 {
        out.push(
          Violation::new(
            HazardReviewRequired,
            Error,
            c.id,
            "",
            "missing SDS/declaration revision reference",
          ),
        )
      }
    }
    for j in (i + 1)..<cargos.length() {
      let other = cargos[j]
      if c.id == other.id {
        out.push(
          Violation::new(
            DuplicateCargo,
            Error,
            c.id,
            other.id,
            "duplicate manifest id",
          ),
        )
      }
      if !c.hazard.class.is_regulated() && !other.hazard.class.is_regulated() {
        continue
      }
      let mut found = false
      for rule in rules.hazard_pairs {
        if (rule.a == c.hazard && rule.b == other.hazard) ||
          (rule.b == c.hazard && rule.a == other.hazard) {
          found = true
          if rule.rule_id.trim().length() == 0 ||
            rule.source.trim().length() == 0 {
            out.push(
              Violation::new(
                HazardInputInvalid,
                Error,
                c.id,
                other.id,
                "pair rule has no id/source",
              ),
            )
          }
          match rule.relation {
            ProhibitSameUnit =>
              out.push(
                Violation::new(
                  HazardSameUnitForbidden,
                  Error,
                  c.id,
                  other.id,
                  "rule " +
                  rule.rule_id +
                  ": " +
                  rule.source +
                  "; no distance or review overrides this prohibition",
                ),
              )
            ReviewRequired => ()
          }
        }
      }
      if !found {
        out.push(
          Violation::new(
            HazardRuleUnknown,
            Error,
            c.id,
            other.id,
            "no relationship for these exact declarations; human assessment and a sourced rule are required",
          ),
        )
      }
    }
  }
  if regulated {
    match rules.hazard_review {
      Some(review) =>
        if review.matches(unit, cargos, rules.hazard_pairs) {
          out.push(
            Violation::new(
              HazardPlanningOnly,
              Warning,
              "",
              unit.id,
              "planning record " +
              review.record_id +
              "; reviewer " +
              review.reviewer +
              "; evidence " +
              review.evidence +
              "; geometry only, transport approval remains external",
            ),
          )
        } else {
          out.push(
            Violation::new(
              HazardReviewRequired,
              Error,
              "",
              unit.id,
              "missing fields or stale manifest/unit/rule snapshot in review",
            ),
          )
        }
      None =>
        out.push(
          Violation::new(
            HazardReviewRequired,
            Error,
            "",
            unit.id,
            "no whole-manifest human review; even one dangerous item requires review",
          ),
        )
    }
  }
  out
}

///|
/// A blocked job retains all goods and findings without manufacturing a split.
fn blocked_plan(
  unit : LoadUnit,
  cargos : Array[Cargo],
  rules : StowRules,
) -> LoadPlan? {
  let invalid = validate_input(unit, cargos, rules)
  let findings = assess_hazards(unit, cargos, rules)
  for v in invalid {
    findings.push(v)
  }
  if is_clear(findings) {
    return None
  }
  let unplaced : Array[Unplaced] = []
  for c in cargos {
    unplaced.push({
      cargo_id: c.id,
      reason: "input or hazard assessment blocked the whole manifest; inspect violations",
    })
  }
  Some({
    unit_id: unit.id,
    unit_kind: unit.kind,
    placements: [],
    unplaced,
    metrics: if invalid.length() == 0 {
      compute_metrics(unit, cargos, [])
    } else {
      {
        ..compute_metrics(LoadUnit::container_20ft(unit.id), [], []),
        cargo_count: cargos.length(),
        capacity_volume_mm3: 0L,
        payload_limit_g: 0,
      }
    },
    violations: findings,
  })
}

///|
pub extend HazardClass with Eq::{equal, not_equal}

///|
pub extend PackingGroup with Eq::{equal, not_equal}

///|
pub extend Hazard with Eq::{equal, not_equal}

///|
pub extend HazardRelation with Eq::{equal, not_equal}

///|
pub extend HazardPairRule with Eq::{equal, not_equal}

///|
pub extend HazardReview with Eq::{equal, not_equal}
