///|
/// Hazardous goods: the segregation table turns "keep them apart" into a number
/// the packer can enforce. Class 1 against class 5.1 needs three metres of
/// clearance, which cannot fit across a 2.352 m container, so one piece has to
/// leave the box and the plan has to say why.
fn main {
  let unit = @moon-stow.LoadUnit::container_20ft("MSKU7654321")
  let explosive = @moon-stow.Cargo::new(
    "UN0004",
    @moon-stow.Dimensions::new(1100, 900, 900),
    300_000,
  ).with_hazard(
    @moon-stow.Hazard::new(
      @moon-stow.HazardClass::parse("1"),
      "UN0004",
      @moon-stow.PackingGroup::II,
    ),
  )
  let oxidizer = @moon-stow.Cargo::new(
    "UN1479",
    @moon-stow.Dimensions::new(1100, 900, 900),
    120_000,
  ).with_hazard(
    @moon-stow.Hazard::new(
      @moon-stow.HazardClass::parse("5.1"),
      "UN1479",
      @moon-stow.PackingGroup::III,
    ),
  )
  let level = @moon-stow.segregation_level(
    @moon-stow.HazardClass::parse("1"),
    @moon-stow.HazardClass::parse("5.1"),
  )
  let needed = @moon-stow.clearance_for_level(level)
  println(
    "class 1 vs 5.1 -> level " +
    level.to_string() +
    ", clearance " +
    @moon-stow.format_m(needed) +
    ", container width " +
    @moon-stow.format_m(unit.dims.width),
  )
  let cargos = [explosive, oxidizer]
  let plan = @moon-stow.pack(unit, cargos, @moon-stow.StowRules::default())
  println("")
  println(@moon-stow.render_text(plan, cargos))
  println("")
  println(@moon-stow.summary_line(plan))
  for u in plan.unplaced {
    println("unplaced " + u.cargo_id + ": " + u.reason)
  }
}
