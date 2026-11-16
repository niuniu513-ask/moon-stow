///|
/// The validator is independent of the packer: this example packs a clean plan,
/// then tampers with two placements by hand and shows every finding. That is what
/// a warehouse system needs — a second opinion on a plan it did not generate.
fn main {
  let unit = @moon-stow.LoadUnit::container_20ft("TAMPER-DEMO")
  let size = @moon-stow.Dimensions::new(1200, 1000, 1000)
  let cargos = [
    @moon-stow.Cargo::new("A", size, 300_000),
    @moon-stow.Cargo::new("B", size, 200_000),
  ]
  let rules = @moon-stow.StowRules::default()
  let plan = @moon-stow.pack(unit, cargos, rules)
  println("packed: " + @moon-stow.summary_line(plan))
  let first = plan.placements[0]
  // A copy of the first item, floating one metre up and shifted 100 mm: it
  // overlaps nothing, but nothing supports it either.
  let ghost : @moon-stow.Placement = {
    cargo_id: first.cargo_id,
    cargo_index: first.cargo_index,
    orientation: first.orientation,
    box: @moon-stow.Aabb::at(
      first.box.min.x + 100,
      first.box.min.y,
      900,
      first.box.size,
    ),
    stop: first.stop,
    layer: 1,
  }
  let tampered = [first, ghost, plan.placements[1]]
  let findings = @moon-stow.verify(unit, cargos, tampered, rules)
  println("")
  println("tampered: " + findings.length().to_string() + " finding(s)")
  for v in findings {
    println(
      "  " +
      @moon-stow.Severity::label(v.severity) +
      "  " +
      @moon-stow.ViolationKind::label(v.kind) +
      "   " +
      v.cargo_id,
    )
  }
  println("")
  println(
    "clean plan is clear: " +
    @moon-stow.is_clear(@moon-stow.verify(unit, cargos, plan.placements, rules)).to_string(),
  )
}
