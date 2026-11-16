///|
/// A loading job as it arrives from an order system: one unit, the goods, and the
/// house rules. This is the input format the CLI and the tests share.
pub(all) struct Scenario {
  unit : LoadUnit
  cargos : Array[Cargo]
  rules : StowRules
} derive(Eq)

///|
pub extend Scenario with Eq::{equal, not_equal}

///|
/// Parse a scenario document. Errors carry a path so a bad order file can be
/// fixed without guessing which line broke.
pub fn parse_scenario(text : String) -> Result[Scenario, String] {
  let root = @json.parse(text) catch {
    _ => return Err("invalid JSON document")
  }
  let unit_json = match obj_get(root, "unit") {
    Some(j) => j
    None => return Err("missing \"unit\"")
  }
  let unit = match parse_unit(unit_json) {
    Some(u) => u
    None => return Err("unit: unknown or incomplete unit description")
  }
  let items = match obj_get(root, "items") {
    Some(j) =>
      match arr_of(j) {
        Some(a) => a
        None => return Err("items: must be an array")
      }
    None => return Err("missing \"items\"")
  }
  let cargos : Array[Cargo] = []
  let mut i = 0
  for item in items {
    match parse_cargo(item) {
      Some(c) => cargos.push(c)
      None => return Err("items[" + i.to_string() + "]: incomplete item")
    }
    i = i + 1
  }
  let rules = match obj_get(root, "rules") {
    Some(j) => parse_rules(j)
    None => StowRules::default()
  }
  Ok({ unit, cargos, rules, })
}

///|
/// Object member lookup that tolerates a non-object JSON value.
fn obj_get(j : Json, key : String) -> Json? {
  if j is Object(map) {
    map.get(key)
  } else {
    None
  }
}

///|
fn arr_of(j : Json) -> Array[Json]? {
  if j is Array(items) {
    Some(items)
  } else {
    None
  }
}

///|
fn str_of(j : Json) -> String? {
  if j is String(s) {
    Some(s)
  } else {
    None
  }
}

///|
fn num_of(j : Json) -> Double? {
  if j is Number(n, ..) {
    Some(n)
  } else {
    None
  }
}

///|
fn bool_of(j : Json) -> Bool? {
  if j is True {
    Some(true)
  } else if j is False {
    Some(false)
  } else {
    None
  }
}

///|
pub fn parse_unit(j : Json) -> LoadUnit? {
  let label = match obj_get(j, "type") {
    Some(v) =>
      match str_of(v) {
        Some(s) => s
        None => return None
      }
    None => return None
  }
  let id = match obj_get(j, "id") {
    Some(v) =>
      match str_of(v) {
        Some(s) => s
        None => label
      }
    None => label
  }
  if label == "container_20ft" {
    Some(LoadUnit::container_20ft(id))
  } else if label == "container_40hc" {
    Some(LoadUnit::container_40hc(id))
  } else if label == "truck_rigid" {
    Some(LoadUnit::truck_rigid(id))
  } else if label == "pallet_eur" {
    Some(LoadUnit::pallet_eur(id))
  } else if label == "pallet_iso" {
    Some(LoadUnit::pallet_iso(id))
  } else if label == "air_uld" {
    Some({
      id,
      kind: AirUld,
      dims: Dimensions::new(3175, 2438, 1626),
      max_payload_g: 6_800_000,
      tare_g: 0,
      floor_limit_g_per_m2: 0,
      axles: [],
      rear_door_at_origin: true,
      max_stack_height_mm: 1626,
    })
  } else {
    None
  }
}

///|
pub fn parse_cargo(j : Json) -> Cargo? {
  let id = match obj_get(j, "id") {
    Some(v) =>
      match str_of(v) {
        Some(s) => s
        None => return None
      }
    None => return None
  }
  let size = match obj_get(j, "size") {
    Some(v) =>
      match arr_of(v) {
        Some(a) => a
        None => return None
      }
    None => return None
  }
  if size.length() < 3 {
    return None
  }
  let l = match num_of(size[0]) {
    Some(n) => n.to_int()
    None => return None
  }
  let w = match num_of(size[1]) {
    Some(n) => n.to_int()
    None => return None
  }
  let h = match num_of(size[2]) {
    Some(n) => n.to_int()
    None => return None
  }
  let weight_g = match number_or(j, "weight_kg") {
    Some(kg) => max_i(0, (kg * 1000.0).to_int())
    None => 0
  }
  // A zero or negative edge is a data entry mistake, not a small carton: reject
  // it here so a bad order file cannot turn into a degenerate placement.
  if l <= 0 || w <= 0 || h <= 0 {
    return None
  }
  let mut cargo = Cargo::new(id, Dimensions::new(l, w, h), weight_g)
  match obj_get(j, "upright") {
    Some(v) =>
      match str_of(v) {
        Some(s) => cargo = cargo.with_upright(upright_of(s))
        None => ()
      }
    None => ()
  }
  match number_or(j, "stop") {
    Some(n) => cargo = cargo.with_stop(n.to_int())
    None => ()
  }
  match number_or(j, "priority") {
    Some(n) => cargo = cargo.with_priority(n.to_int())
    None => ()
  }
  match number_or(j, "gap_mm") {
    Some(n) => cargo = cargo.with_gap(n.to_int())
    None => ()
  }
  match obj_get(j, "group") {
    Some(v) =>
      match str_of(v) {
        Some(s) => cargo = cargo.with_group(s)
        None => ()
      }
    None => ()
  }
  if bool_or(j, "fragile", false) == Some(true) {
    cargo = cargo.fragile_item()
  }
  if bool_or(j, "stackable", true) == Some(false) {
    cargo = cargo.with_stack_limit(1, 0)
  }
  match number_or(j, "max_layers") {
    Some(n) =>
      if n > 0.0 {
        let top = match number_or(j, "top_load_kg") {
          Some(kg) => (kg * 1000.0).to_int()
          None => 60_000
        }
        cargo = cargo.with_stack_limit(n.to_int(), top)
      }
    None => ()
  }
  match obj_get(j, "hazard") {
    Some(v) => {
      let hc = match obj_get(v, "class") {
        Some(c) =>
          match str_of(c) {
            Some(s) => HazardClass::parse(s)
            None => None
          }
        None => None
      }
      if hc.is_regulated() {
        let un = match obj_get(v, "un") {
          Some(u) =>
            match str_of(u) {
              Some(s) => s
              None => ""
            }
          None => ""
        }
        let group = match obj_get(v, "group") {
          Some(g) =>
            match str_of(g) {
              Some(s) => packing_group_of(s)
              None => NotApplicable
            }
          None => NotApplicable
        }
        cargo = cargo.with_hazard(Hazard::new(hc, un, group))
      }
    }
    None => ()
  }
  Some(cargo)
}

///|
pub fn parse_rules(j : Json) -> StowRules {
  let mut rules = StowRules::default()
  match number_or(j, "min_support_permille") {
    Some(n) => rules = rules.with_support(n.to_int())
    None => ()
  }
  match number_or(j, "cog_margin_permille") {
    Some(n) => rules = rules.with_cog_margin(n.to_int())
    None => ()
  }
  match number_or(j, "max_stack_layers") {
    Some(n) => rules = rules.with_layer_cap(n.to_int())
    None => ()
  }
  if bool_or(j, "overstow", true) == Some(false) {
    rules = { ..rules, enforce_overstow: false, }
  }
  if bool_or(j, "axles", true) == Some(false) {
    rules = { ..rules, enforce_axles: false, }
  }
  rules
}

///|
pub fn upright_of(text : String) -> UprightPolicy {
  if text == "fixed" || text == "this_side_up" {
    Fixed
  } else if text == "free" || text == "any" {
    Free
  } else {
    KeepUpright
  }
}

///|
pub fn packing_group_of(text : String) -> PackingGroup {
  if text == "I" || text == "1" {
    I
  } else if text == "II" || text == "2" {
    II
  } else if text == "III" || text == "3" {
    III
  } else {
    NotApplicable
  }
}

///|
fn number_or(j : Json, key : String) -> Double? {
  match obj_get(j, key) {
    Some(v) => num_of(v)
    None => None
  }
}

///|
fn bool_or(j : Json, key : String, fallback : Bool) -> Bool? {
  match obj_get(j, key) {
    Some(v) =>
      match bool_of(v) {
        Some(b) => Some(b)
        None => Some(fallback)
      }
    None => None
  }
}

///|
/// JSON string escaping (RFC 8259): only the mandatory escapes, so ids stay
/// readable.
pub fn json_escape(text : String) -> String {
  let mut out = ""
  for i in 0..<text.length() {
    let ch = text[i:i + 1].to_owned()
    if ch == "\\" {
      out = out + "\\\\"
    } else if ch == "\"" {
      out = out + "\\\""
    } else if ch == "\n" {
      out = out + "\\n"
    } else if ch == "\r" {
      out = out + "\\r"
    } else if ch == "\t" {
      out = out + "\\t"
    } else {
      out = out + ch
    }
  }
  out
}

///|
pub fn json_str(text : String) -> String {
  "\"" + json_escape(text) + "\""
}

///|
/// The plan as JSON, stable field order, for diffing two packer versions in CI.
pub fn plan_to_json(plan : LoadPlan) -> String {
  let m = plan.metrics
  let mut out = "{\n  " +
    json_str("unit_id") +
    ": " +
    json_str(plan.unit_id) +
    ",\n"
  out = out +
    "  " +
    json_str("unit_kind") +
    ": " +
    json_str(plan.unit_kind.label()) +
    ",\n"
  out = out + "  " + json_str("metrics") + ": {\n"
  out = out +
    "    " +
    json_str("placed_count") +
    ": " +
    m.placed_count.to_string() +
    ",\n"
  out = out +
    "    " +
    json_str("cargo_count") +
    ": " +
    m.cargo_count.to_string() +
    ",\n"
  out = out +
    "    " +
    json_str("volume_utilization_permille") +
    ": " +
    m.volume_utilization_permille.to_string() +
    ",\n"
  out = out +
    "    " +
    json_str("weight_utilization_permille") +
    ": " +
    m.weight_utilization_permille.to_string() +
    ",\n"
  out = out +
    "    " +
    json_str("stack_height_mm") +
    ": " +
    m.stack_height_mm.to_string() +
    ",\n"
  out = out +
    "    " +
    json_str("cog_x_mm") +
    ": " +
    m.cog_x_mm.to_string() +
    ",\n"
  out = out +
    "    " +
    json_str("cog_y_mm") +
    ": " +
    m.cog_y_mm.to_string() +
    ",\n"
  out = out +
    "    " +
    json_str("cog_z_mm") +
    ": " +
    m.cog_z_mm.to_string() +
    "\n  },\n"
  let ordered = sort_placements(plan.placements)
  out = out + "  " + json_str("placements") + ": [\n"
  let mut n = 0
  for p in ordered {
    out = out +
      "    {" +
      json_str("cargo_id") +
      ": " +
      json_str(p.cargo_id) +
      ", " +
      json_str("stop") +
      ": " +
      p.stop.to_string() +
      ", " +
      json_str("layer") +
      ": " +
      p.layer.to_string() +
      ", " +
      json_str("orientation") +
      ": " +
      json_str(p.orientation.label()) +
      ", " +
      json_str("x_mm") +
      ": " +
      p.box.min.x.to_string() +
      ", " +
      json_str("y_mm") +
      ": " +
      p.box.min.y.to_string() +
      ", " +
      json_str("z_mm") +
      ": " +
      p.box.min.z.to_string() +
      ", " +
      json_str("length_mm") +
      ": " +
      p.box.size.length.to_string() +
      ", " +
      json_str("width_mm") +
      ": " +
      p.box.size.width.to_string() +
      ", " +
      json_str("height_mm") +
      ": " +
      p.box.size.height.to_string() +
      "}"
    n = n + 1
    if n < ordered.length() {
      out = out + ","
    }
    out = out + "\n"
  }
  out = out + "  ],\n"
  out = out + "  " + json_str("unplaced") + ": [\n"
  let mut k = 0
  for u in plan.unplaced {
    out = out +
      "    {" +
      json_str("cargo_id") +
      ": " +
      json_str(u.cargo_id) +
      ", " +
      json_str("reason") +
      ": " +
      json_str(u.reason) +
      "}"
    k = k + 1
    if k < plan.unplaced.length() {
      out = out + ","
    }
    out = out + "\n"
  }
  out = out + "  ],\n"
  out = out + "  " + json_str("findings") + ": [\n"
  let mut f = 0
  for v in plan.violations {
    out = out +
      "    {" +
      json_str("kind") +
      ": " +
      json_str(v.kind.label()) +
      ", " +
      json_str("severity") +
      ": " +
      json_str(v.severity.label()) +
      ", " +
      json_str("cargo_id") +
      ": " +
      json_str(v.cargo_id) +
      ", " +
      json_str("detail") +
      ": " +
      json_str(v.detail) +
      "}"
    f = f + 1
    if f < plan.violations.length() {
      out = out + ","
    }
    out = out + "\n"
  }
  out = out + "  ]\n}\n"
  out
}

///|
pub fn plan_to_string(plan : LoadPlan) -> String {
  plan_to_json(plan)
}

///|
test "scenario: parse a job file and pack it" {
  let text = "{\"unit\":{\"type\":\"container_20ft\",\"id\":\"CONT9\"},\"items\":[{\"id\":\"A\",\"size\":[1200,1000,800],\"weight_kg\":20},{\"id\":\"B\",\"size\":[800,600,600],\"weight_kg\":8,\"stop\":1}],\"rules\":{\"min_support_permille\":800}}"
  let scenario = match parse_scenario(text) {
    Ok(s) => s
    Err(message) => {
      println("unexpected parse failure: " + message)
      return
    }
  }
  assert_eq(scenario.unit.id, "CONT9")
  assert_eq(scenario.cargos.length(), 2)
  assert_eq(scenario.rules.min_support_permille, 800)
  let plan = pack(scenario.unit, scenario.cargos, scenario.rules)
  assert_eq(plan.placements.length(), 2)
  let json = plan_to_string(plan)
  assert_true(json.contains("\"cargo_id\": \"A\""))
}

///|
test "scenario: broken documents are rejected with a reason" {
  let missing = parse_scenario("{\"items\":[]}")
  assert_true(missing is Err(_))
  let broken = parse_scenario("{not json")
  assert_true(broken is Err(_))
}
