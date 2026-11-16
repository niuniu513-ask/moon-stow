///|
/// Multi-drop truck: three delivery stops loaded back to front, a manifest per
/// stop, a JSON plan for the warehouse system and an SVG drawing for the driver.
fn main {
  let unit = @moon-stow.LoadUnit::truck_rigid("TRK-77")
  let cargos = [
    @moon-stow.Cargo::new(
      "PAL-A",
      @moon-stow.Dimensions::new(1200, 800, 1200),
      180_000,
    ).with_stop(0),
    @moon-stow.Cargo::new(
      "PAL-B",
      @moon-stow.Dimensions::new(1200, 800, 1000),
      150_000,
    ).with_stop(0),
    @moon-stow.Cargo::new(
      "PAL-C",
      @moon-stow.Dimensions::new(1200, 1000, 1400),
      220_000,
    ).with_stop(1),
    @moon-stow.Cargo::new(
      "PAL-D",
      @moon-stow.Dimensions::new(1200, 1000, 900),
      190_000,
    ).with_stop(2),
    @moon-stow.Cargo::new(
      "PAL-E",
      @moon-stow.Dimensions::new(1000, 800, 800),
      120_000,
    ).with_stop(2),
  ]
  let plan = @moon-stow.pack(unit, cargos, @moon-stow.StowRules::default())
  println(@moon-stow.render_manifest(plan, cargos))
  println("")
  println(@moon-stow.summary_line(plan))
  let svg = @moon-stow.render_svg(plan, unit, 900)
  println("")
  println("svg bytes: " + svg.length().to_string())
  let doc = @moon-stow.plan_to_string(plan)
  println(doc[0:400].to_owned())
}
