///|
/// All lengths in `moon-stow` are integer millimetres and all weights are
/// integer grams. Integer arithmetic keeps every packing decision, every
/// reported metric and every verification result bit-for-bit reproducible,
/// which matters because a loading plan is an auditable document: two runs of
/// the same scenario must produce the same plan and the same numbers.

///|
pub const MM_PER_M : Int32 = 1000

///|
pub const G_PER_KG : Int32 = 1000

///|
pub const MM2_PER_M2 : Int32 = 1_000_000

///|
pub fn min_i(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}

///|
pub fn max_i(a : Int32, b : Int32) -> Int32 {
  if a > b {
    a
  } else {
    b
  }
}

///|
pub fn min64(a : Int64, b : Int64) -> Int64 {
  if a < b {
    a
  } else {
    b
  }
}

///|
pub fn mm_to_m(value : Int32) -> Double {
  value.to_double() / 1000.0
}

///|
pub fn g_to_kg(value : Int32) -> Double {
  value.to_double() / 1000.0
}

///|
/// Volume of an axis aligned box in cubic millimetres. Returned as Int64 because
/// a 45HC container already exceeds 32-bit range (about 7.6e10 mm^3).
pub fn volume_mm3(d : Dimensions) -> Int64 {
  d.length.to_int64() * d.width.to_int64() * d.height.to_int64()
}

///|
pub fn floor_area_mm2(d : Dimensions) -> Int64 {
  d.length.to_int64() * d.width.to_int64()
}

///|
/// Human readable cubic metres with three decimals, e.g. `67.634`.
pub fn format_m3(volume : Int64) -> String {
  let whole = volume / 1_000_000_000L
  let frac = volume % 1_000_000_000L
  let frac3 = frac / 1_000_000L
  let padded = if frac3 < 10L {
    "00" + frac3.to_string()
  } else if frac3 < 100L {
    "0" + frac3.to_string()
  } else {
    frac3.to_string()
  }
  whole.to_string() + "." + padded
}

///|
/// Human readable kilograms with three decimals.
pub fn format_kg(grams : Int32) -> String {
  if grams >= 1_000_000 {
    // tonnes read better than six digit kilogram counts on a dock sheet
    let tonnes = grams / 1_000_000
    let rest = grams % 1_000_000 / 100_000
    return tonnes.to_string() + "." + rest.to_string() + " t"
  }
  let whole = grams / G_PER_KG
  let frac = grams % G_PER_KG
  let padded = if frac < 10 {
    "00" + frac.to_string()
  } else if frac < 100 {
    "0" + frac.to_string()
  } else {
    frac.to_string()
  }
  whole.to_string() + "." + padded + " kg"
}

///|
/// Percentage with one decimal, used for every utilisation figure.
pub fn format_pct(permille : Int32) -> String {
  let whole = permille / 10
  let frac = permille % 10
  whole.to_string() + "." + frac.to_string() + "%"
}

///|
/// Ratio in permille (1000 == 1.0) without floating point.
pub fn ratio_permille(part : Int64, total : Int64) -> Int32 {
  if total <= 0L {
    return 0
  }
  let scaled = part * 1000L
  let rounded = scaled + total / 2L
  (rounded / total).to_int()
}

///|
pub fn clamp_int(value : Int32, low : Int32, high : Int32) -> Int32 {
  if value < low {
    low
  } else if value > high {
    high
  } else {
    value
  }
}

///|
test "units: formatting" {
  assert_eq(format_kg(12_400), "12.400 kg")
  assert_eq(format_kg(28_200_000), "28.2 t")
  assert_eq(format_kg(950), "0.950 kg")
  assert_eq(format_m3(2_500_000_000L), "2.500")
  assert_eq(format_pct(857), "85.7%")
  assert_eq(ratio_permille(1L, 3L), 333)
}

///|
/// Metres with two decimals, e.g. `"6.35 m"`, used for clearances.
pub fn format_m(value : Int32) -> String {
  let whole = value / 1000
  let rest = value % 1000
  let centi = rest / 10
  let padded = if centi < 10 {
    "0" + centi.to_string()
  } else {
    centi.to_string()
  }
  whole.to_string() + "." + padded + " m"
}

///|
/// Floor area in square metres, three decimals: `2.416 m2`.
pub fn format_m2(area_mm2 : Int64) -> String {
  let whole = area_mm2 / 1_000_000L
  let frac = area_mm2 % 1_000_000L
  let scaled = frac * 1000L / 1_000_000L
  whole.to_string() + "." + pad_left(scaled.to_string(), 3) + " m2"
}

///|
/// Left padding with an arbitrary fill string, for aligned report columns.
pub fn pad_start(text : String, width : Int32, fill : String) -> String {
  if text.length() >= width {
    return text
  }
  let mut out = ""
  let mut i = text.length()
  while i < width {
    out = out + fill
    i = i + 1
  }
  out + text
}
