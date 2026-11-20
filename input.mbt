///|
/// Planning bounds keep all integer calculations defined: edges up to 30 m,
/// at most 1000 items, total mass (including declared axle tare) <= 2e9 g,
/// and manifest volume <= 8e15 mm3. Invalid inputs are rejected, not clamped.
fn valid_dimensions(d : Dimensions) -> Bool {
  d.is_positive() &&
  d.length <= 30_000 &&
  d.width <= 30_000 &&
  d.height <= 30_000
}

///|
pub fn validate_input(
  unit : LoadUnit,
  cargos : Array[Cargo],
  rules : StowRules,
) -> Array[Violation] {
  let out : Array[Violation] = []
  if unit.id.trim().length() == 0 ||
    !valid_dimensions(unit.dims) ||
    unit.max_payload_g < 0 ||
    unit.tare_g < 0 ||
    unit.floor_limit_g_per_m2 < 0 ||
    unit.max_stack_height_mm <= 0 ||
    unit.max_stack_height_mm > 30_000 {
    out.push(
      Violation::new(
        InputInvalid,
        Error,
        "",
        unit.id,
        "invalid unit id, dimensions, height or load limits",
      ),
    )
  }
  if rules.min_support_permille < 0 ||
    rules.min_support_permille > 1000 ||
    rules.cog_margin_permille < 0 ||
    rules.cog_margin_permille > 1000 ||
    rules.max_stack_layers < 0 {
    out.push(
      Violation::new(
        InputInvalid,
        Error,
        "",
        "",
        "invalid support, gravity or layer threshold",
      ),
    )
  }
  let mut empty = 0L
  let mut previous = -1
  for axle in unit.axles {
    if axle.position_mm <= previous ||
      axle.position_mm < 0 ||
      axle.position_mm > unit.dims.length ||
      axle.max_load_g <= 0 ||
      axle.empty_load_g < 0 {
      out.push(
        Violation::new(
          InputInvalid,
          Error,
          "",
          unit.id,
          "axles require increasing in-bounds positions and nonnegative tare loads",
        ),
      )
    }
    previous = axle.position_mm
    empty = empty + axle.empty_load_g.to_int64()
  }
  if unit.axles.length() > 0 && empty != unit.tare_g.to_int64() {
    out.push(
      Violation::new(
        InputInvalid,
        Error,
        "",
        unit.id,
        "explicit empty axle loads must sum to unit tare",
      ),
    )
  }
  let mut total_weight = empty
  let mut volume = 0L
  if cargos.length() > 1000 {
    out.push(
      Violation::new(InputInvalid, Error, "", "", "manifest exceeds 1000 items"),
    )
  }
  for c in cargos {
    if c.id.trim().length() == 0 ||
      !valid_dimensions(c.dims) ||
      c.weight_g < 0 ||
      c.max_top_load_g < 0 ||
      c.max_stack_layers <= 0 ||
      c.min_gap_mm < 0 ||
      c.min_gap_mm > 30_000 ||
      c.stop < 0 {
      out.push(
        Violation::new(
          InputInvalid,
          Error,
          c.id,
          "",
          "invalid cargo id, dimensions, weight, stop, gap or stacking limit",
        ),
      )
    }
    total_weight = total_weight + c.weight_g.to_int64()
    if valid_dimensions(c.dims) {
      volume = volume + c.dims.volume_mm3()
    }
  }
  if total_weight > 2_000_000_000L ||
    total_weight < 0L ||
    volume > 8_000_000_000_000_000L {
    out.push(
      Violation::new(
        InputInvalid,
        Error,
        "",
        "",
        "manifest exceeds supported total weight or volume range",
      ),
    )
  }
  out
}
