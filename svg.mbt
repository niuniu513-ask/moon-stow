///|
/// Colour per stop, so a multi-drop plan reads at a glance: door stop is the
/// warm colour, the far stop the cool one.
fn stop_colour(stop : Int32) -> String {
  let palette = [
    "#e4572e", "#f4a259", "#8cb369", "#4c9f70", "#2e86ab", "#5d5fef", "#845ec2",
    "#c34a36",
  ]
  let i = if stop < 0 { 0 } else { stop % palette.length() }
  palette[i]
}

///|
/// Minimal XML escaping for ids that came from a customer spreadsheet.
pub fn xml_escape(text : String) -> String {
  let mut out = ""
  for i in 0..<text.length() {
    let ch = text[i:i + 1].to_owned()
    if ch == "&" {
      out = out + "&amp;"
    } else if ch == "<" {
      out = out + "&lt;"
    } else if ch == ">" {
      out = out + "&gt;"
    } else if ch == "\"" {
      out = out + "&quot;"
    } else {
      out = out + ch
    }
  }
  out
}

///|
/// Top view: length runs left to right, width top to bottom, the door is on the
/// left edge because the packer builds plans from the door inwards.
pub fn render_top_view(
  plan : LoadPlan,
  unit : LoadUnit,
  width_px : Int32,
) -> String {
  let envelope = unit.envelope()
  let scale = scale_permille(width_px, envelope.length)
  let height_px = apply_scale(envelope.width, scale)
  let mut out = "<g id=\"top-view\">\n"
  out = out +
    "  <rect x=\"0\" y=\"0\" width=\"" +
    width_px.to_string() +
    "\" height=\"" +
    height_px.to_string() +
    "\" fill=\"#f7f7f5\" stroke=\"#333333\" stroke-width=\"2\"/>\n"
  for p in sort_placements(plan.placements) {
    let x = apply_scale(p.box.min.x, scale)
    let y = apply_scale(p.box.min.y, scale)
    let w = apply_scale(p.box.size.length, scale)
    let h = apply_scale(p.box.size.width, scale)
    out = out +
      "  <rect x=\"" +
      x.to_string() +
      "\" y=\"" +
      y.to_string() +
      "\" width=\"" +
      w.to_string() +
      "\" height=\"" +
      h.to_string() +
      "\" fill=\"" +
      stop_colour(p.stop) +
      "\" fill-opacity=\"0.55\" stroke=\"#222222\" stroke-width=\"1\"/>\n"
    if w >= 46 && h >= 16 {
      out = out +
        "  <text x=\"" +
        (x + 4).to_string() +
        "\" y=\"" +
        (y + 14).to_string() +
        "\" font-size=\"11\" fill=\"#111111\">" +
        xml_escape(p.cargo_id) +
        "</text>\n"
    }
  }
  out = out +
    "  <text x=\"6\" y=\"" +
    (height_px - 8).to_string() +
    "\" font-size=\"11\" fill=\"#666666\">door</text>\n"
  out = out + "</g>"
  out
}

///|
/// Side view: length left to right, height bottom up. This is the view that shows
/// whether a stack is top heavy.
pub fn render_side_view(
  plan : LoadPlan,
  unit : LoadUnit,
  width_px : Int32,
) -> String {
  let envelope = unit.envelope()
  let scale = scale_permille(width_px, envelope.length)
  let height_px = apply_scale(envelope.height, scale)
  let mut out = "<g id=\"side-view\">\n"
  out = out +
    "  <rect x=\"0\" y=\"0\" width=\"" +
    width_px.to_string() +
    "\" height=\"" +
    height_px.to_string() +
    "\" fill=\"#f7f7f5\" stroke=\"#333333\" stroke-width=\"2\"/>\n"
  for p in sort_placements(plan.placements) {
    let x = apply_scale(p.box.min.x, scale)
    let w = apply_scale(p.box.size.length, scale)
    let h = apply_scale(p.box.size.height, scale)
    let y = height_px - apply_scale(p.box.max_z(), scale)
    out = out +
      "  <rect x=\"" +
      x.to_string() +
      "\" y=\"" +
      y.to_string() +
      "\" width=\"" +
      w.to_string() +
      "\" height=\"" +
      h.to_string() +
      "\" fill=\"" +
      stop_colour(p.stop) +
      "\" fill-opacity=\"0.55\" stroke=\"#222222\" stroke-width=\"1\"/>\n"
  }
  out = out + "</g>"
  out
}

///|
/// Full drawing: a title line with the key numbers, a top view and a side view,
/// plus a legend naming the stops. The result is a standalone SVG document.
pub fn render_svg(plan : LoadPlan, unit : LoadUnit, width_px : Int32) -> String {
  render_svg_for(plan, width_px, unit.envelope(), unit.kind.label())
}

///|
fn render_svg_for(
  plan : LoadPlan,
  width_px : Int32,
  envelope : Dimensions,
  kind_label : String,
) -> String {
  let top = render_top_view(plan, envelope_as_unit(plan, envelope), width_px)
  let side = render_side_view(plan, envelope_as_unit(plan, envelope), width_px)
  let top_h = apply_scale(
    envelope.width,
    scale_permille(width_px, envelope.length),
  )
  let side_h = apply_scale(
    envelope.height,
    scale_permille(width_px, envelope.length),
  )
  let total_h = top_h + side_h + 96
  let mut out = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" +
    width_px.to_string() +
    "\" height=\"" +
    total_h.to_string() +
    "\" viewBox=\"0 0 " +
    width_px.to_string() +
    " " +
    total_h.to_string() +
    "\">\n"
  out = out + "<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n"
  out = out +
    "<text x=\"4\" y=\"20\" font-size=\"15\" font-family=\"sans-serif\" fill=\"#111111\">" +
    xml_escape(kind_label) +
    " " +
    xml_escape(plan.unit_id) +
    " - " +
    summary_line(plan) +
    "</text>\n"
  out = out + "<g transform=\"translate(0,32)\">\n" + top + "\n</g>\n"
  out = out +
    "<g transform=\"translate(0," +
    (top_h + 56).to_string() +
    ")\">\n" +
    side +
    "\n</g>\n"
  out = out + legend(plan, width_px, top_h + side_h + 78) + "\n"
  out = out + "</svg>\n"
  out
}

///|
fn envelope_as_unit(plan : LoadPlan, envelope : Dimensions) -> LoadUnit {
  {
    id: plan.unit_id,
    kind: plan.unit_kind,
    dims: envelope,
    max_payload_g: plan.metrics.payload_limit_g,
    tare_g: 0,
    floor_limit_g_per_m2: 0,
    axles: [],
    rear_door_at_origin: true,
    max_stack_height_mm: envelope.height,
  }
}

///|
fn legend(plan : LoadPlan, width_px : Int32, y : Int32) -> String {
  let stops = stop_weights(plan.placements, [])
  let _ = stops
  let seen : Array[Int32] = []
  for p in plan.placements {
    let mut found = false
    for s in seen {
      if s == p.stop {
        found = true
      }
    }
    if !found {
      seen.push(p.stop)
    }
  }
  sort_ints(seen)
  let mut out = "<g id=\"legend\">"
  let mut x = 6
  for s in seen {
    out = out +
      "<rect x=\"" +
      x.to_string() +
      "\" y=\"" +
      y.to_string() +
      "\" width=\"12\" height=\"12\" fill=\"" +
      stop_colour(s) +
      "\" fill-opacity=\"0.55\" stroke=\"#222222\"/>"
    out = out +
      "<text x=\"" +
      (x + 16).to_string() +
      "\" y=\"" +
      (y + 11).to_string() +
      "\" font-size=\"11\" font-family=\"sans-serif\" fill=\"#333333\">stop " +
      s.to_string() +
      "</text>"
    x = x + 70
    let _ = width_px
  }
  out + "</g>"
}

///|
/// Scale in permille: pixels = mm * scale / 1000.
pub fn scale_permille(target_px : Int32, span_mm : Int32) -> Int32 {
  if span_mm <= 0 {
    return 1
  }
  max_i(1, target_px * 1000 / span_mm)
}

///|
fn apply_scale(mm : Int32, scale : Int32) -> Int32 {
  mm * scale / 1000
}

///|
test "svg: top view draws one rect per placement" {
  let unit = LoadUnit::container_20ft("C1")
  let cargos = [
    Cargo::new("A", Dimensions::new(1200, 1000, 800), 10_000),
    Cargo::new("B", Dimensions::new(800, 600, 600), 5_000),
  ]
  let plan = pack(unit, cargos, StowRules::default())
  let top = render_top_view(plan, unit, 600)
  let mut rects = 0
  let mut i = 0
  while i + 5 <= top.length() {
    if top[i:i + 5].to_owned() == "<rect" {
      rects = rects + 1
    }
    i = i + 1
  }
  // one envelope + one per placement
  assert_eq(rects, 3)
  let doc = render_svg(plan, unit, 600)
  assert_true(doc.contains("<svg"))
  assert_true(doc.contains("</svg>"))
  assert_true(doc.contains("top-view"))
  assert_true(doc.contains("side-view"))
}
