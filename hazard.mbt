///|
/// Dangerous-goods classes, numbered as in the UN Model Regulations / IMDG code.
/// `None` means the cargo is not regulated and never constrains a neighbour.
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
} derive(Eq)

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
pub fn HazardClass::parse(text : String) -> HazardClass {
  match text.trim() {
    "1" => Explosive
    "2.1" => GasFlammable
    "2.2" => GasNonFlammable
    "2.3" => GasToxic
    "3" => FlammableLiquid
    "4.1" => FlammableSolid
    "4.2" => SpontaneouslyCombustible
    "4.3" => DangerousWhenWet
    "5.1" => Oxidizer
    "5.2" => OrganicPeroxide
    "6.1" => Toxic
    "6.2" => Infectious
    "7" => Radioactive
    "8" => Corrosive
    "9" => Miscellaneous
    _ => None
  }
}

///|
/// Packing group as used for liquids: I is the most dangerous.
pub(all) enum PackingGroup {
  NotApplicable
  I
  II
  III
} derive(Eq)

///|
/// A declared dangerous good. `None` is the default for ordinary freight, so a
/// plan that never mentions hazards still carries a well defined value.
pub(all) struct Hazard {
  class : HazardClass
  un_number : String
  packing_group : PackingGroup
} derive(Eq)

///|
pub fn Hazard::none() -> Hazard {
  { class: None, un_number: "", packing_group: NotApplicable, }
}

///|
pub fn Hazard::new(
  class : HazardClass,
  un_number : String,
  group : PackingGroup,
) -> Hazard {
  { class, un_number, packing_group: group, }
}

///|
/// Segregation requirement expressed as one of five levels. The numeric ladder
/// keeps the table readable and lets a customer replace it with their own.
pub fn segregation_level(a : HazardClass, b : HazardClass) -> Int32 {
  let i = a.index()
  let j = b.index()
  if i == 0 || j == 0 {
    return 0
  }
  max_i(segregation_row(i)[j], segregation_row(j)[i])
}

///|
/// One row of the 16x16 segregation matrix; values are 0..4. Row `i` is filled
/// with the requirement for class `i` against every class `j`.
///
/// The defaults follow the shape of IMDG 7.2.4 (away from / separated from /
/// separated by a complete compartment) reduced to a single clearance per pair.
/// They are deliberately conservative for explosives and oxidizers, which are
/// the two pairs where a wrong answer is expensive.
fn segregation_row(i : Int32) -> Array[Int32] {
  match i {
    1 =>
      // Explosives: keep a complete compartment away from every other class.
      [0, 0, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4]
    2 =>
      // Flammable gas.
      [0, 4, 0, 1, 1, 1, 2, 2, 2, 2, 2, 1, 2, 2, 1, 1]
    3 =>
      // Non-flammable, non-toxic gas.
      [0, 4, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0]
    4 =>
      // Toxic gas.
      [0, 4, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    5 =>
      // Flammable liquid.
      [0, 4, 1, 1, 1, 0, 1, 1, 1, 2, 2, 1, 1, 1, 1, 0]
    6 =>
      // Flammable solid.
      [0, 4, 2, 1, 1, 1, 0, 2, 2, 2, 2, 1, 1, 1, 1, 0]
    7 =>
      // Spontaneously combustible.
      [0, 4, 2, 1, 1, 1, 2, 0, 2, 2, 2, 1, 1, 1, 1, 1]
    8 =>
      // Dangerous when wet.
      [0, 4, 2, 1, 1, 1, 2, 2, 0, 2, 2, 1, 1, 1, 1, 1]
    9 =>
      // Oxidizer.
      [0, 4, 2, 1, 1, 2, 2, 2, 2, 0, 2, 1, 1, 1, 2, 1]
    10 =>
      // Organic peroxide.
      [0, 4, 2, 1, 1, 2, 2, 2, 2, 2, 0, 1, 1, 1, 2, 1]
    11 =>
      // Toxic (oral, dermal, inhalation).
      [0, 4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0]
    12 =>
      // Infectious substance.
      [0, 4, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1]
    13 =>
      // Radioactive.
      [0, 4, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1]
    14 =>
      // Corrosive.
      [0, 4, 1, 1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 0, 1]
    15 =>
      // Miscellaneous.
      [0, 4, 1, 0, 1, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1, 0]
    _ => [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  }
}

///|
/// Minimum clearance in millimetres implied by a segregation level. The mapping
/// is the one used by the bundled rule set; a company can pass its own table of
/// clearances to `StowRules` instead.
pub fn clearance_for_level(level : Int32) -> Int32 {
  match level {
    0 => 0
    1 => 3_000
    2 => 6_000
    3 => 12_000
    4 => 24_000
    _ => 24_000
  }
}

///|
/// Name of a level, used in reports.
pub fn segregation_label(level : Int32) -> String {
  match level {
    0 => "none"
    1 => "away from"
    2 => "separated from"
    3 => "separated by one compartment"
    4 => "separated longitudinally by a complete compartment"
    _ => "unspecified"
  }
}

///|
test "hazard: identical non regulated cargo never separates" {
  assert_eq(segregation_level(None, Corrosive), 0)
  assert_eq(segregation_level(FlammableLiquid, None), 0)
}

///|
test "hazard: table is symmetric" {
  let classes = [
    Explosive,
    GasFlammable,
    GasNonFlammable,
    GasToxic,
    FlammableLiquid,
    FlammableSolid,
    SpontaneouslyCombustible,
    DangerousWhenWet,
    Oxidizer,
    OrganicPeroxide,
    Toxic,
    Infectious,
    Radioactive,
    Corrosive,
    Miscellaneous,
  ]
  for a in classes {
    for b in classes {
      assert_eq(segregation_level(a, b), segregation_level(b, a))
    }
  }
}

///|
test "hazard: oxidizer and flammable solid must be separated" {
  assert_eq(segregation_level(Oxidizer, FlammableSolid), 2)
  assert_eq(clearance_for_level(2), 6_000)
}

///|
pub extend HazardClass with Eq::{equal, not_equal}

///|
pub extend PackingGroup with Eq::{equal, not_equal}

///|
pub extend Hazard with Eq::{equal, not_equal}
