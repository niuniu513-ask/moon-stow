///|
/// All declaration references and reviewer records below are fictional fixtures.
/// The local prohibition illustrates chemistry evidence, not IMDG compliance.
fn main {
  let unit = @moon-stow.LoadUnit::container_20ft("DEMO-C1")
  let acid = @moon-stow.Cargo::new(
    "HCL-30PCT",
    @moon-stow.Dimensions::new(600, 400, 400),
    20_000,
  ).with_hazard(
    @moon-stow.Hazard::new(@moon-stow.Corrosive, "UN1789", @moon-stow.II).with_declaration(
      "DEMO HCl 30%; SDS-r1; drums; no subsidiary declaration; 20kg",
    ),
  )
  let bleach = @moon-stow.Cargo::new(
    "NACLO-12PCT",
    @moon-stow.Dimensions::new(600, 400, 400),
    20_000,
  ).with_hazard(
    @moon-stow.Hazard::new(@moon-stow.Corrosive, "UN1791", @moon-stow.III).with_declaration(
      "DEMO active chlorine 12%; SDS-r1; drums; no subsidiary declaration; 20kg",
    ),
  )
  let rule : @moon-stow.HazardPairRule = {
    a: acid.hazard,
    b: bleach.hazard,
    relation: @moon-stow.ProhibitSameUnit,
    rule_id: "LOCAL-ACID-HYPOCHLORITE-1",
    source: "local no-co-load policy: ICSC 1119 Chemical Dangers, acids release chlorine; https://www.inchem.org/documents/icsc/icsc/eics1119.htm; NOT an IMDG rule",
  }
  println(
    "DEMO ONLY: no actual SDS, qualified reviewer or carrier approval is supplied.",
  )
  let forbidden = @moon-stow.pack(unit, [acid, bleach], {
    ..@moon-stow.StowRules::default(),
    hazard_pairs: [rule],
  })
  println(
    "1. Same class 8, specific substance conflict: no distance can override prohibition",
  )
  println(@moon-stow.render_text(forbidden, [acid, bleach]))
  let unknown = @moon-stow.pack(
    unit,
    [acid, bleach],
    @moon-stow.StowRules::default(),
  )
  println(
    "2. Unknown relationship: hold whole manifest, never assume compatible",
  )
  println(@moon-stow.render_text(unknown, [acid, bleach]))
  let cargos = [acid]
  let held = @moon-stow.pack(unit, cargos, @moon-stow.StowRules::default())
  println("3. Single dangerous item: still held without whole-manifest review")
  println(@moon-stow.summary_line(held))
  let review = @moon-stow.HazardReview::new(
    unit,
    cargos,
    [],
    "DEMO-REVIEW-1",
    "FICTIONAL reviewer",
    "DEMO fixture only; real review must cover SDS/classification, subsidiary risks, quantities, packing, IMDG edition/DGL/special rules, CTU conditions, carrier acceptance, date and decision",
  )
  let rules = {
    ..@moon-stow.StowRules::default(),
    hazard_review: Some(review),
  }
  println(
    "4. Simulated completed external review: geometry planning only, not permission to ship",
  )
  println(@moon-stow.render_text(@moon-stow.pack(unit, cargos, rules), cargos))
}
