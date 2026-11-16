///|
/// Carton selection for an order: choose boxes from a small catalogue, report
/// the freight cost and the void fill.
fn main {
  let catalog = [
    @moon-stow.CartonSpec::new(
      "XS",
      @moon-stow.Dimensions::new(250, 200, 150),
      3_000,
      45,
    ),
    @moon-stow.CartonSpec::new(
      "S",
      @moon-stow.Dimensions::new(350, 250, 200),
      8_000,
      70,
    ),
    @moon-stow.CartonSpec::new(
      "M",
      @moon-stow.Dimensions::new(450, 350, 300),
      15_000,
      110,
    ),
    @moon-stow.CartonSpec::new(
      "L",
      @moon-stow.Dimensions::new(600, 450, 400),
      25_000,
      165,
    ),
  ]
  let goods = [
    @moon-stow.Cargo::new("MUG", @moon-stow.Dimensions::new(120, 120, 110), 400),
    @moon-stow.Cargo::new("BOOK", @moon-stow.Dimensions::new(240, 170, 40), 700),
    @moon-stow.Cargo::new(
      "LAMP",
      @moon-stow.Dimensions::new(300, 300, 400),
      1_800,
    ),
    @moon-stow.Cargo::new(
      "CABLE",
      @moon-stow.Dimensions::new(180, 180, 60),
      250,
    ),
  ]
  let result = @moon-stow.cartonize(
    catalog,
    goods,
    @moon-stow.StowRules::default(),
  )
  let mut index = 1
  for pick in result.picks {
    println(
      "carton " +
      index.to_string() +
      ": " +
      pick.carton.id +
      " holds " +
      pick.plan.placements.length().to_string() +
      " item(s), " +
      pick.carton.inner.length.to_string() +
      "x" +
      pick.carton.inner.width.to_string() +
      "x" +
      pick.carton.inner.height.to_string() +
      " mm",
    )
    index = index + 1
  }
  println(
    "cost: " +
    (result.total_cost_cents / 100).to_string() +
    "." +
    pad2(result.total_cost_cents % 100) +
    " currency units",
  )
  println("void fill: " + @moon-stow.format_pct(result.void_fill_permille))
  for u in result.unpacked {
    println("unpacked: " + u.cargo_id + " (" + u.reason + ")")
  }
}

///|
fn pad2(value : Int32) -> String {
  if value < 10 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}
