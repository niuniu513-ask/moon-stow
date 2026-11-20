///|
/// Indices of the placements that directly support `index`: their top face is
/// exactly at the box's bottom face and their footprint overlaps.
pub fn supports_of(
  placements : Array[Placement],
  index : Int32,
) -> Array[Int32] {
  let out : Array[Int32] = []
  let target = placements[index]
  for i in 0..<placements.length() {
    if i != index {
      let other = placements[i]
      if other.box.max_z() == target.box.min.z &&
        other.box.footprint_overlap(target.box) > 0 {
        out.push(i)
      }
    }
  }
  out
}

///|
/// Full plan verification. Every check is independent so a single bad placement
/// produces exactly the violations it deserves, which is what makes the report
/// usable as a pre-load checklist rather than a single "plan invalid" flag.
pub fn verify(
  unit : LoadUnit,
  cargos : Array[Cargo],
  placements : Array[Placement],
  rules : StowRules,
) -> Array[Violation] {
  let out = assess_hazards(unit, cargos, rules)
  let invalid = validate_input(unit, cargos, rules)
  for v in invalid {
    out.push(v)
  }
  if invalid.length() > 0 {
    return out
  }
  let layers = compute_layers(placements)
  let envelope = unit.envelope()
  // 1. identity checks
  let seen : Array[String] = []
  for p in placements {
    let mut duplicate = false
    for s in seen {
      if s == p.cargo_id {
        duplicate = true
      }
    }
    if duplicate {
      out.push(
        Violation::new(
          DuplicateCargo,
          Error,
          p.cargo_id,
          "",
          "cargo placed twice",
        ),
      )
    } else {
      seen.push(p.cargo_id)
    }
    if p.cargo_index < 0 || p.cargo_index >= cargos.length() {
      out.push(
        Violation::new(
          UnknownCargo,
          Error,
          p.cargo_id,
          "",
          "cargo index out of range",
        ),
      )
    } else if cargos[p.cargo_index].id != p.cargo_id {
      out.push(
        Violation::new(
          UnknownCargo,
          Error,
          p.cargo_id,
          cargos[p.cargo_index].id,
          "id does not match index",
        ),
      )
    }
  }
  for i in 0..<cargos.length() {
    let mut found = false
    for p in placements {
      if p.cargo_id == cargos[i].id {
        found = true
      }
    }
    if !found {
      out.push(
        Violation::new(MissingCargo, Error, cargos[i].id, "", "no placement"),
      )
    }
  }
  // 2. per placement geometry and orientation
  for p in placements {
    if p.cargo_index < 0 || p.cargo_index >= cargos.length() {
      continue
    }
    let cargo = cargos[p.cargo_index]
    let mut allowed = false
    for o in cargo.upright.allowed() {
      if o == p.orientation {
        allowed = true
      }
    }
    if !allowed {
      out.push(
        Violation::new(
          OrientationNotAllowed,
          Error,
          p.cargo_id,
          "",
          "orientation " + p.orientation.label() + " not allowed",
        ),
      )
    }
    let expected = cargo.dims.oriented(p.orientation)
    if expected != p.box.size {
      out.push(
        Violation::new(
          OrientationNotAllowed,
          Error,
          p.cargo_id,
          "",
          "box size does not match oriented cargo size",
        ),
      )
    }
    if !p.box.fits_within(envelope) {
      out.push(
        Violation::new(
          OutOfBounds,
          Error,
          p.cargo_id,
          "",
          "box leaves the usable envelope",
        ),
      )
    }
    if p.box.size.height > envelope.height {
      out.push(
        Violation::new(
          HeightExceeded,
          Error,
          p.cargo_id,
          "",
          "item is taller than the usable height",
        ),
      )
    }
  }
  // Reject invalid coordinates before support, pressure or graph calculations.
  for p in placements {
    if !valid_dimensions(p.box.size) ||
      p.box.min.x < 0 ||
      p.box.min.y < 0 ||
      p.box.min.z < 0 ||
      p.box.min.x > 30_000 ||
      p.box.min.y > 30_000 ||
      p.box.min.z > 30_000 {
      out.push(
        Violation::new(
          InputInvalid,
          Error,
          p.cargo_id,
          "",
          "invalid placement geometry",
        ),
      )
      return out
    }
  }
  // 3. collisions
  for i in 0..<placements.length() {
    for j in (i + 1)..<placements.length() {
      let a = placements[i]
      let b = placements[j]
      if a.cargo_index >= 0 &&
        a.cargo_index < cargos.length() &&
        b.cargo_index >= 0 &&
        b.cargo_index < cargos.length() {
        let required = max_i(
          cargos[a.cargo_index].min_gap_mm,
          cargos[b.cargo_index].min_gap_mm,
        )
        // A declared clearance is a lateral requirement: a cargo stacked on
        // another touches it vertically and cannot also keep a horizontal gap.
        // Only pairs that share a height band are compared.
        if required > 0 &&
          a.box.shares_height(b.box) &&
          a.box.side_gap(b.box) < required {
          out.push(
            Violation::new(
              CargoGap,
              Error,
              a.cargo_id,
              b.cargo_id,
              "declared lateral clearance " +
              required.to_string() +
              " mm not met; no regulatory meaning",
            ),
          )
        }
      }
      if a.box.intersects(b.box) {
        out.push(
          Violation::new(
            Overlap,
            Error,
            a.cargo_id,
            b.cargo_id,
            "boxes interpenetrate",
          ),
        )
      }
    }
  }
  // 4. support, stacking and top load
  for i in 0..<placements.length() {
    let p = placements[i]
    if p.box.min.z > 0 {
      let below : Array[Aabb] = []
      for s in supports_of(placements, i) {
        below.push(placements[s].box)
      }
      let own_area = p.box.size.length * p.box.size.width
      let supported = p.box.supported_area(below)
      let ratio = if own_area <= 0 {
        0
      } else {
        (supported.to_int64() * 1000L / own_area.to_int64()).to_int()
      }
      if below.length() == 0 {
        out.push(
          Violation::new(
            InsufficientSupport,
            Error,
            p.cargo_id,
            "",
            "no box underneath",
          ),
        )
      } else if ratio < rules.min_support_permille {
        out.push(
          Violation::new(
            InsufficientSupport,
            Error,
            p.cargo_id,
            "",
            "supported ratio " +
            format_pct(ratio) +
            " below " +
            format_pct(rules.min_support_permille),
          ),
        )
      }
    }
    if p.cargo_index < 0 || p.cargo_index >= cargos.length() {
      continue
    }
    let cargo = cargos[p.cargo_index]
    let layer = layers[i]
    if p.stop != cargo.stop || p.layer != layer {
      out.push(
        Violation::new(
          PlacementMetadata,
          Error,
          p.cargo_id,
          "",
          "stop or layer metadata was changed independently of cargo/support graph",
        ),
      )
    }
    if layer > cargo.max_stack_layers {
      out.push(
        Violation::new(
          StackLayersExceeded,
          Error,
          p.cargo_id,
          "",
          "layer " +
          layer.to_string() +
          " above own limit " +
          cargo.max_stack_layers.to_string(),
        ),
      )
    }
    if rules.max_stack_layers > 0 && layer > rules.max_stack_layers {
      out.push(
        Violation::new(
          StackLayersExceeded,
          Error,
          p.cargo_id,
          "",
          "layer " +
          layer.to_string() +
          " above global cap " +
          rules.max_stack_layers.to_string(),
        ),
      )
    }
    for s in supports_of(placements, i) {
      let support = placements[s]
      if support.cargo_index < 0 || support.cargo_index >= cargos.length() {
        continue
      }
      let support_cargo = cargos[support.cargo_index]
      if !support_cargo.stackable {
        out.push(
          Violation::new(
            TopLoadExceeded,
            Error,
            p.cargo_id,
            support.cargo_id,
            "cargo below cannot carry load",
          ),
        )
      }
      if layer > support_cargo.max_stack_layers {
        out.push(
          Violation::new(
            StackLayersExceeded,
            Error,
            p.cargo_id,
            support.cargo_id,
            "stack taller than the support allows",
          ),
        )
      }
    }
    for upper in upper_items(placements, i) {
      if layers[upper] > cargo.max_stack_layers {
        out.push(
          Violation::new(
            StackLayersExceeded,
            Error,
            placements[upper].cargo_id,
            p.cargo_id,
            "an ancestor support limits the full stack height",
          ),
        )
      }
    }
    let top = load_on(placements, cargos, i)
    if top > cargo.max_top_load_g {
      out.push(
        Violation::new(
          TopLoadExceeded,
          Error,
          p.cargo_id,
          "",
          "load on top " +
          format_kg(top) +
          " kg exceeds " +
          format_kg(cargo.max_top_load_g) +
          " kg",
        ),
      )
    }
    if top > 0 && !cargo.stackable {
      out.push(
        Violation::new(
          TopLoadExceeded,
          Error,
          p.cargo_id,
          "",
          "non stackable cargo carries load",
        ),
      )
    }
  }
  // 5. unit level limits
  let mut total_weight = 0
  for p in placements {
    if p.cargo_index >= 0 && p.cargo_index < cargos.length() {
      total_weight = total_weight + cargos[p.cargo_index].weight_g
    }
  }
  if unit.max_payload_g > 0 && total_weight > unit.max_payload_g {
    out.push(
      Violation::new(
        PayloadExceeded,
        Error,
        "",
        unit.id,
        "payload " +
        format_kg(total_weight) +
        " kg over limit " +
        format_kg(unit.max_payload_g) +
        " kg",
      ),
    )
  }
  let pressure = max_floor_pressure(placements, cargos)
  if unit.floor_limit_g_per_m2 > 0 && pressure > unit.floor_limit_g_per_m2 {
    out.push(
      Violation::new(
        FloorLimitExceeded,
        Error,
        "",
        unit.id,
        "point load " + pressure.to_string() + " g/m2 over limit",
      ),
    )
  }
  // 6. axles and balance
  if rules.enforce_axles && unit.axles.length() > 0 {
    let loads = axle_loads(unit, placements, cargos)
    for i in 0..<loads.length() {
      if loads[i] > unit.axles[i].max_load_g {
        out.push(
          Violation::new(
            AxleOverload,
            Error,
            "",
            "axle-" + (i + 1).to_string(),
            "axle load " +
            format_kg(loads[i]) +
            " kg over limit " +
            format_kg(unit.axles[i].max_load_g) +
            " kg",
          ),
        )
      }
    }
  }
  match center_of_gravity(placements, cargos) {
    Some(cog) => {
      let (px, py) = cog_offset_permille(cog, envelope)
      let limit = rules.cog_margin_permille
      if px > limit || px < -limit || py > limit || py < -limit {
        out.push(
          Violation::new(
            Imbalance,
            Warning,
            "",
            unit.id,
            "centre of gravity offset x=" +
            px.to_string() +
            " y=" +
            py.to_string() +
            " permille",
          ),
        )
      }
      if !cog_inside_floor(cog, envelope) {
        out.push(
          Violation::new(
            Imbalance,
            Error,
            "",
            unit.id,
            "centre of gravity outside the floor",
          ),
        )
      }
    }
    None => ()
  }
  // 7. Whole-manifest hazard assessment is performed before geometry.
  // 8. overstow: nothing may sit in front of an earlier delivery
  if rules.enforce_overstow {
    for i in 0..<placements.length() {
      for j in (i + 1)..<placements.length() {
        let a = placements[i]
        let b = placements[j]
        if a.cargo_index < 0 ||
          a.cargo_index >= cargos.length() ||
          b.cargo_index < 0 ||
          b.cargo_index >= cargos.length() {
          continue
        }
        let a_stop = cargos[a.cargo_index].stop
        let b_stop = cargos[b.cargo_index].stop
        if a_stop == b_stop {
          continue
        }
        let overlap_y = min_i(a.box.max_y(), b.box.max_y()) -
          max_i(a.box.min.y, b.box.min.y)
        let overlap_z = min_i(a.box.max_z(), b.box.max_z()) -
          max_i(a.box.min.z, b.box.min.z)
        if overlap_y <= 0 || overlap_z <= 0 {
          continue
        }
        let a_in_front = if unit.rear_door_at_origin {
          a.box.max_x() <= b.box.min.x
        } else {
          b.box.max_x() <= a.box.min.x
        }
        let b_in_front = if unit.rear_door_at_origin {
          b.box.max_x() <= a.box.min.x
        } else {
          a.box.max_x() <= b.box.min.x
        }
        if a_in_front && a_stop > b_stop {
          out.push(
            Violation::new(
              Overstow,
              Error,
              a.cargo_id,
              b.cargo_id,
              "stop " +
              a.stop.to_string() +
              " blocks stop " +
              b.stop.to_string(),
            ),
          )
        }
        if b_in_front && b_stop > a_stop {
          out.push(
            Violation::new(
              Overstow,
              Error,
              b.cargo_id,
              a.cargo_id,
              "stop " +
              b.stop.to_string() +
              " blocks stop " +
              a.stop.to_string(),
            ),
          )
        }
      }
    }
  }
  out
}

///|
/// True when the plan has no violation at `Error` level.
pub fn is_clear(violations : Array[Violation]) -> Bool {
  let mut clear = true
  for v in violations {
    if v.severity == Error {
      clear = false
    }
  }
  clear
}

///|
pub fn count_by_severity(
  violations : Array[Violation],
  severity : Severity,
) -> Int32 {
  let mut n = 0
  for v in violations {
    if v.severity == severity {
      n = n + 1
    }
  }
  n
}

///|
/// Layer of every placement, computed in one pass. Supports always sit lower, so
/// sorting by the bottom face makes the dependency order explicit and avoids the
/// quadratic recursion of a per item query.
pub fn compute_layers(placements : Array[Placement]) -> Array[Int32] {
  let n = placements.length()
  let layers : Array[Int32] = []
  for _ in 0..<n {
    layers.push(1)
  }
  let order : Array[Int32] = []
  for i in 0..<n {
    order.push(i)
  }
  let mut i = 1
  while i < n {
    let item = order[i]
    let mut j = i - 1
    let mut done = false
    while j >= 0 && !done {
      if placements[order[j]].box.min.z > placements[item].box.min.z {
        order[j + 1] = order[j]
        j = j - 1
      } else {
        done = true
      }
    }
    order[j + 1] = item
    i = i + 1
  }
  for index in order {
    let mut deepest = 0
    let box = placements[index].box
    for k in 0..<n {
      if k != index {
        let other = placements[k].box
        if other.max_z() == box.min.z && other.footprint_overlap(box) > 0 {
          deepest = max_i(deepest, layers[k])
        }
      }
    }
    layers[index] = deepest + 1
  }
  layers
}
