///|
/// One line an operator can paste into a chat window.
pub fn summary_line(plan : LoadPlan) -> String {
  let m = plan.metrics
  let errors = count_by_severity(plan.violations, Error)
  let warnings = count_by_severity(plan.violations, Warning)
  plan.unit_kind.label() +
  " " +
  plan.unit_id +
  ": " +
  m.placed_count.to_string() +
  "/" +
  m.cargo_count.to_string() +
  " pieces, " +
  format_pct(m.volume_utilization_permille) +
  " volume, " +
  format_kg(m.total_weight_g) +
  " / " +
  format_kg(m.payload_limit_g) +
  ", " +
  errors.to_string() +
  " error(s), " +
  warnings.to_string() +
  " warning(s)"
}

///|
/// Human readable plan for the dock floor: header, metrics, the placement table
/// and every problem found.
pub fn render_text(plan : LoadPlan, cargos : Array[Cargo]) -> String {
  let m = plan.metrics
  let mut out = ""
  out = out +
    "LOAD PLAN " +
    plan.unit_id +
    " (" +
    plan.unit_kind.label() +
    ")\n"
  out = out + "------------------------------------------------------------\n"
  out = out +
    "pieces      " +
    m.placed_count.to_string() +
    " of " +
    m.cargo_count.to_string() +
    "\n"
  out = out +
    "volume      " +
    format_m3(m.used_volume_mm3) +
    " of " +
    format_m3(m.capacity_volume_mm3) +
    " (" +
    format_pct(m.volume_utilization_permille) +
    ")\n"
  out = out +
    "weight      " +
    format_kg(m.total_weight_g) +
    " of " +
    format_kg(m.payload_limit_g) +
    " (" +
    format_pct(m.weight_utilization_permille) +
    ")\n"
  out = out +
    "floor       " +
    format_m2(m.floor_used_mm2) +
    " footprint, stack " +
    format_m(m.stack_height_mm) +
    "\n"
  out = out +
    "centre      x " +
    format_m(m.cog_x_mm) +
    ", y " +
    format_m(m.cog_y_mm) +
    ", z " +
    format_m(m.cog_z_mm) +
    "\n"
  out = out + "\n"
  out = out +
    "  #  cargo            stop layer orient  x         y         z         size                 kg\n"
  let mut n = 1
  for p in sort_placements(plan.placements) {
    let weight = match cargo_of(cargos, p.cargo_index) {
      Some(c) => format_kg(c.weight_g)
      None => "-"
    }
    out = out +
      pad_start(n.to_string(), 3, " ") +
      "  " +
      pad_right(p.cargo_id, 16) +
      " " +
      pad_start(p.stop.to_string(), 4, " ") +
      " " +
      pad_start(p.layer.to_string(), 5, " ") +
      " " +
      pad_right(p.orientation.label(), 7) +
      " " +
      pad_right(p.box.min.x.to_string(), 9) +
      " " +
      pad_right(p.box.min.y.to_string(), 9) +
      " " +
      pad_right(p.box.min.z.to_string(), 9) +
      " " +
      pad_right(
        p.box.size.length.to_string() +
        "x" +
        p.box.size.width.to_string() +
        "x" +
        p.box.size.height.to_string(),
        20,
      ) +
      " " +
      weight +
      "\n"
    n = n + 1
  }
  if plan.unplaced.length() > 0 {
    out = out + "\nUNPLACED\n"
    for u in plan.unplaced {
      out = out + "  " + pad_right(u.cargo_id, 16) + " " + u.reason + "\n"
    }
  }
  if plan.violations.length() > 0 {
    out = out + "\nFINDINGS\n"
    for v in plan.violations {
      out = out +
        "  " +
        pad_right(v.severity.label(), 8) +
        " " +
        pad_right(v.kind.label(), 26) +
        " " +
        pad_right(v.cargo_id, 14) +
        " " +
        v.detail +
        "\n"
    }
  }
  out
}

///|
/// Markdown version of the same report, for a pull request comment or a wiki.
pub fn render_markdown(plan : LoadPlan, cargos : Array[Cargo]) -> String {
  let m = plan.metrics
  let mut out = ""
  out = out + "## Load plan " + plan.unit_id + "\n\n"
  out = out + "| metric | value |\n|---|---|\n"
  out = out +
    "| pieces | " +
    m.placed_count.to_string() +
    " / " +
    m.cargo_count.to_string() +
    " |\n"
  out = out +
    "| volume | " +
    format_m3(m.used_volume_mm3) +
    " / " +
    format_m3(m.capacity_volume_mm3) +
    " (" +
    format_pct(m.volume_utilization_permille) +
    ") |\n"
  out = out +
    "| weight | " +
    format_kg(m.total_weight_g) +
    " / " +
    format_kg(m.payload_limit_g) +
    " (" +
    format_pct(m.weight_utilization_permille) +
    ") |\n"
  out = out + "| stack height | " + format_m(m.stack_height_mm) + " |\n"
  out = out +
    "| centre of gravity | " +
    format_m(m.cog_x_mm) +
    ", " +
    format_m(m.cog_y_mm) +
    ", " +
    format_m(m.cog_z_mm) +
    " |\n\n"
  out = out +
    "| # | cargo | stop | layer | orientation | position (mm) | size (mm) | kg |\n"
  out = out + "|---|---|---|---|---|---|---|---|\n"
  let mut n = 1
  for p in sort_placements(plan.placements) {
    let weight = match cargo_of(cargos, p.cargo_index) {
      Some(c) => format_kg(c.weight_g)
      None => "-"
    }
    out = out +
      "| " +
      n.to_string() +
      " | " +
      p.cargo_id +
      " | " +
      p.stop.to_string() +
      " | " +
      p.layer.to_string() +
      " | " +
      p.orientation.label() +
      " | " +
      p.box.min.x.to_string() +
      ", " +
      p.box.min.y.to_string() +
      ", " +
      p.box.min.z.to_string() +
      " | " +
      p.box.size.length.to_string() +
      " x " +
      p.box.size.width.to_string() +
      " x " +
      p.box.size.height.to_string() +
      " | " +
      weight +
      " |\n"
    n = n + 1
  }
  if plan.unplaced.length() > 0 {
    out = out + "\n### Unplaced\n\n"
    for u in plan.unplaced {
      out = out + "- **" + u.cargo_id + "** - " + u.reason + "\n"
    }
  }
  if plan.violations.length() > 0 {
    out = out + "\n### Findings\n\n"
    for v in plan.violations {
      out = out +
        "- **" +
        v.severity.label() +
        "** **" +
        v.kind.label() +
        "** " +
        v.cargo_id +
        ": " +
        v.detail +
        "\n"
    }
  }
  out
}

///|
/// Machine readable placement list (RFC 4180 quoting for the id field).
pub fn render_csv(plan : LoadPlan, cargos : Array[Cargo]) -> String {
  let mut out = "cargo_id,stop,layer,orientation,x_mm,y_mm,z_mm,length_mm,width_mm,height_mm,weight_kg\n"
  for p in sort_placements(plan.placements) {
    let weight = match cargo_of(cargos, p.cargo_index) {
      Some(c) => format_kg(c.weight_g)
      None => "0 kg"
    }
    out = out +
      csv_field(p.cargo_id) +
      "," +
      p.stop.to_string() +
      "," +
      p.layer.to_string() +
      "," +
      p.orientation.label() +
      "," +
      p.box.min.x.to_string() +
      "," +
      p.box.min.y.to_string() +
      "," +
      p.box.min.z.to_string() +
      "," +
      p.box.size.length.to_string() +
      "," +
      p.box.size.width.to_string() +
      "," +
      p.box.size.height.to_string() +
      "," +
      weight +
      "\n"
  }
  out
}

///|
/// Delivery manifest: what leaves the unit at each stop, in drop order, with the
/// weight per stop so the driver can plan the tail lift.
pub fn render_manifest(plan : LoadPlan, cargos : Array[Cargo]) -> String {
  let stops = stop_weights(plan.placements, cargos)
  let mut out = "MANIFEST " + plan.unit_id + "\n"
  for pair in stops {
    let (stop, weight) = pair
    out = out + "\nSTOP " + stop.to_string() + "  (" + format_kg(weight) + ")\n"
    for p in sort_placements(plan.placements) {
      if p.stop == stop {
        out = out +
          "  " +
          pad_right(p.cargo_id, 18) +
          " layer " +
          p.layer.to_string() +
          "  at " +
          format_m(p.box.min.x) +
          "\n"
      }
    }
  }
  out
}

///|
pub fn csv_field(text : String) -> String {
  let escaped = replace_all(text, "\"", "\"\"")
  "\"" + escaped + "\""
}

///|
pub fn replace_all(
  text : String,
  needle : String,
  replacement : String,
) -> String {
  if needle.length() == 0 {
    return text
  }
  let mut out = ""
  let mut i = 0
  let n = text.length()
  while i < n {
    if i + needle.length() <= n &&
      text[i:i + needle.length()].to_owned() == needle {
      out = out + replacement
      i = i + needle.length()
    } else {
      out = out + text[i:i + 1].to_owned()
      i = i + 1
    }
  }
  out
}

///|
pub fn pad_right(text : String, width : Int32) -> String {
  if text.length() >= width {
    return text
  }
  let mut out = text
  while out.length() < width {
    out = out + " "
  }
  out
}

///|
fn cargo_of(cargos : Array[Cargo], index : Int32) -> Cargo? {
  if index >= 0 && index < cargos.length() {
    Some(cargos[index])
  } else {
    None
  }
}

///|
test "report: summary counts pieces and findings" {
  let cargos = [
    Cargo::new("A", Dimensions::new(1000, 800, 600), 10_000),
    Cargo::new("B", Dimensions::new(500, 400, 300), 2_000),
  ]
  let unit = LoadUnit::container_20ft("CONT")
  let plan = pack(unit, cargos, StowRules::default())
  let line = summary_line(plan)
  assert_true(line.contains("2/2 pieces"))
  assert_true(line.contains("CONT"))
  let text = render_text(plan, cargos)
  assert_true(text.contains("LOAD PLAN CONT"))
  let csv = render_csv(plan, cargos)
  assert_true(csv.contains("cargo_id,stop,layer"))
  let manifest = render_manifest(plan, cargos)
  assert_true(manifest.contains("STOP 0"))
}
