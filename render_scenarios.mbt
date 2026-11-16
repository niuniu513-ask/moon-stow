///|
/// Renderers are the part a customer actually reads, so their contract is
/// pinned down here: unit identity, one row per piece, no floating point noise.

///|
fn count_lines(text : String) -> Int32 {
  // Counting removed newlines keeps this helper free of any string iteration
  // API that could drift between core versions.
  let stripped = replace_all(text, "\n", "")
  text.length() - stripped.length()
}

///|
test "report: text report names the unit and every piece" {
  let cargos = [
    Cargo::new("P1", Dimensions::new(1200, 1000, 900), 18_000),
    Cargo::new("P2", Dimensions::new(1200, 1000, 900), 18_000).with_stop(2),
  ]
  let unit = LoadUnit::container_20ft("CONT1")
  let plan = pack(unit, cargos, StowRules::default())
  let text = render_text(plan, cargos)
  assert_true(text.contains("LOAD PLAN CONT1"))
  assert_true(text.contains("P1"))
  assert_true(text.contains("P2"))
  assert_true(text.contains("pieces"))
  assert_eq(plan.placements.length(), 2)
}

///|
test "report: csv has a header and one row per placement" {
  let cargos = [
    Cargo::new("A", Dimensions::new(800, 600, 600), 9_000),
    Cargo::new("B", Dimensions::new(800, 600, 600), 9_000),
    Cargo::new("C", Dimensions::new(800, 600, 600), 9_000),
  ]
  let unit = LoadUnit::pallet_eur("P1")
  let plan = pack(unit, cargos, StowRules::default())
  let csv = render_csv(plan, cargos)
  assert_true(csv.contains("cargo_id,stop,layer,orientation"))
  assert_eq(count_lines(csv), plan.placements.length() + 1)
}

///|
test "report: markdown keeps the placement table" {
  let cargos = [Cargo::new("M1", Dimensions::new(600, 400, 400), 6_000)]
  let unit = LoadUnit::pallet_iso("P2")
  let plan = pack(unit, cargos, StowRules::default())
  let md = render_markdown(plan, cargos)
  assert_true(md.contains("|"))
  assert_true(md.contains("M1"))
}

///|
test "report: manifest groups pieces by stop" {
  let cargos = [
    Cargo::new("S1", Dimensions::new(800, 600, 600), 9_000).with_stop(1),
    Cargo::new("S2", Dimensions::new(800, 600, 600), 9_000).with_stop(3),
  ]
  let unit = LoadUnit::truck_rigid("T1")
  let plan = pack(unit, cargos, StowRules::default())
  let manifest = render_manifest(plan, cargos)
  assert_true(manifest.contains("MANIFEST T1"))
  assert_true(manifest.contains("STOP 1"))
  assert_true(manifest.contains("STOP 3"))
}

///|
test "report: csv_field quotes and doubles inner quotes" {
  assert_eq(csv_field("plain"), "\"plain\"")
  assert_eq(csv_field("a,b"), "\"a,b\"")
  assert_eq(csv_field("say \"hi\""), "\"say \"\"hi\"\"\"")
}

///|
test "report: summary line reads like an operator note" {
  let cargos = [
    Cargo::new("Q1", Dimensions::new(1200, 1000, 900), 18_000),
    Cargo::new("Q2", Dimensions::new(1200, 1000, 900), 18_000),
  ]
  let unit = LoadUnit::container_20ft("CONT9")
  let plan = pack(unit, cargos, StowRules::default())
  let line = summary_line(plan)
  assert_true(line.contains("2/2 pieces"))
  assert_true(line.contains(" kg / "))
  assert_true(line.contains(" error(s), "))
}

///|
test "svg: projections are well formed and carry no NaN" {
  let cargos = [Cargo::new("V1", Dimensions::new(1000, 800, 700), 12_000)]
  let unit = LoadUnit::container_20ft("C1")
  let plan = pack(unit, cargos, StowRules::default())
  let doc = render_svg(plan, unit, 640)
  assert_true(doc.contains("<svg"))
  assert_true(doc.contains("</svg>"))
  assert_true(doc.contains("top-view"))
  assert_true(doc.contains("side-view"))
  assert_true(doc.contains("NaN") == false)
}

///|
test "units: distances and areas render with fixed decimals" {
  assert_eq(format_m(6350), "6.35 m")
  assert_eq(format_m(300), "0.30 m")
  assert_eq(format_m2(2_416_000L), "2.416 m2")
  assert_eq(pad_start("7", 3, "0"), "007")
  assert_eq(pad_right("ab", 4), "ab  ")
  assert_eq(clamp_int(9, 0, 5), 5)
  assert_eq(min_i(3, 8), 3)
  assert_eq(max_i(3, 8), 8)
}
