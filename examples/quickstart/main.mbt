///|
/// Quickstart: pack four boxes into a 20 ft container and print the report.
fn main {
  let unit = @moon-stow.LoadUnit::container_20ft("MSKU1234567")
  let cargos = [
    @moon-stow.Cargo::new(
      "TV-55",
      @moon-stow.Dimensions::new(1350, 850, 780),
      22_000,
    ),
    @moon-stow.Cargo::new(
      "CHAIR",
      @moon-stow.Dimensions::new(700, 700, 950),
      8_000,
    ),
    @moon-stow.Cargo::new(
      "DESK",
      @moon-stow.Dimensions::new(1600, 900, 300),
      34_000,
    )
    .fragile_item()
    .with_upright(@moon-stow.Fixed),
    @moon-stow.Cargo::new(
      "BOX-1",
      @moon-stow.Dimensions::new(600, 400, 400),
      5_000,
    ),
    @moon-stow.Cargo::new(
      "BOX-2",
      @moon-stow.Dimensions::new(600, 400, 400),
      5_000,
    ),
  ]
  let plan = @moon-stow.pack(unit, cargos, @moon-stow.StowRules::default())
  println(@moon-stow.render_text(plan, cargos))
  println(@moon-stow.summary_line(plan))
}
