///|
/// Pallet building: shelf layers on a euro pallet, then the same goods pushed
/// through the general packer so the two strategies can be compared.
fn main {
  let unit = @moon-stow.LoadUnit::pallet_eur("EUR-01")
  let cargos : Array[@moon-stow.Cargo] = []
  for i in 0..<12 {
    cargos.push(
      @moon-stow.Cargo::new(
        "CTN-" + i.to_string(),
        @moon-stow.Dimensions::new(400, 300, 250),
        7_000,
      ),
    )
  }
  let shelf = @moon-stow.palletize(
    unit,
    cargos,
    @moon-stow.StowRules::default(),
  )
  println("shelf layers:")
  println(@moon-stow.summary_line(shelf))
  let free = @moon-stow.pack(unit, cargos, @moon-stow.StowRules::default())
  println("extreme point heuristic:")
  println(@moon-stow.summary_line(free))
  println("")
  println(@moon-stow.render_text(shelf, cargos))
}
