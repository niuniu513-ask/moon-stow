///|
fn acid_cargo(id : String) -> Cargo {
  Cargo::new(id, Dimensions::new(600, 400, 400), 20_000).with_hazard(
    Hazard::new(Corrosive, "UN1789", II).with_declaration(
      "DEMO-HCL-30pct-SDS-r1; approved drum; 20kg",
    ),
  )
}

///|
fn bleach_cargo() -> Cargo {
  Cargo::new("HYPOCHLORITE", Dimensions::new(600, 400, 400), 20_000).with_hazard(
    Hazard::new(Corrosive, "UN1791", III).with_declaration(
      "DEMO-active-chlorine-12pct-SDS-r1; approved drum; 20kg",
    ),
  )
}

///|
fn acid_bleach_rule() -> HazardPairRule {
  {
    a: acid_cargo("ACID").hazard,
    b: bleach_cargo().hazard,
    relation: ProhibitSameUnit,
    rule_id: "LOCAL-ACID-HYPOCHLORITE-1",
    source: "local no-co-load policy based on ICSC 1119 Chemical Dangers (acid releases chlorine); not an IMDG ruling",
  }
}

///|
fn has_hazard_kind(findings : Array[Violation], kind : ViolationKind) -> Bool {
  for f in findings {
    if f.kind == kind {
      return true
    }
  }
  false
}

///|
fn demo_review(
  unit : LoadUnit,
  cargos : Array[Cargo],
  pairs : Array[HazardPairRule],
) -> HazardReview {
  HazardReview::new(
    unit, cargos, pairs, "DEMO-REVIEW-1", "fictional reviewer for tests only", "DEMO only: SDS revisions, composition, subsidiary risks, quantities, packaging, current IMDG DGL/special segregation, CTU conditions and carrier acceptance checked outside engine; no real approval",
  )
}

///|
test "hazard: same class acid and bleach prohibited regardless of distance or review" {
  let unit = LoadUnit::container_40hc("C")
  let cargos = [acid_cargo("ACID"), bleach_cargo()]
  let pairs = [acid_bleach_rule()]
  let rules = {
    ..StowRules::default(),
    hazard_pairs: pairs,
    hazard_review: Some(demo_review(unit, cargos, pairs)),
  }
  let plan = pack(unit, cargos, rules)
  assert_eq(plan.placements.length(), 0)
  assert_eq(plan.unplaced.length(), 2)
  assert_true(has_hazard_kind(plan.violations, HazardSameUnitForbidden))
  let placements : Array[Placement] = [
    {
      cargo_id: "ACID",
      cargo_index: 0,
      orientation: LWH,
      box: Aabb::at(0, 0, 0, cargos[0].dims),
      stop: 0,
      layer: 1,
    },
    {
      cargo_id: "HYPOCHLORITE",
      cargo_index: 1,
      orientation: LWH,
      box: Aabb::at(10_000, 0, 0, cargos[1].dims),
      stop: 0,
      layer: 1,
    },
  ]
  assert_true(
    has_hazard_kind(
      verify(unit, cargos, placements, rules),
      HazardSameUnitForbidden,
    ),
  )
  assert_true(pack_all(unit, cargos, rules) is None)
  let reversed_rules = {
    ..rules,
    hazard_pairs: [{ ..pairs[0], a: pairs[0].b, b: pairs[0].a, }],
  }
  assert_true(
    has_hazard_kind(
      assess_hazards(unit, cargos, reversed_rules),
      HazardSameUnitForbidden,
    ),
  )
}

///|
test "hazard: unknown pair stays blocked even with a review; ordinary neighbours also need a relationship" {
  let unit = LoadUnit::container_20ft("C")
  let cargos = [
    acid_cargo("ACID"),
    Cargo::new("FOOD", Dimensions::new(400, 400, 400), 5_000),
  ]
  let rules = {
    ..StowRules::default(),
    hazard_review: Some(demo_review(unit, cargos, [])),
  }
  let findings = assess_hazards(unit, cargos, rules)
  assert_true(has_hazard_kind(findings, HazardRuleUnknown))
  assert_false(is_clear(findings))
  assert_eq(pack(unit, cargos, rules).placements.length(), 0)
}

///|
test "hazard: single item still needs review; reviewed plan remains planning only" {
  let unit = LoadUnit::container_20ft("C")
  let cargos = [acid_cargo("ACID")]
  assert_eq(pack(unit, cargos, StowRules::default()).placements.length(), 0)
  let rules = {
    ..StowRules::default(),
    hazard_review: Some(demo_review(unit, cargos, [])),
  }
  let plan = pack(unit, cargos, rules)
  assert_eq(plan.placements.length(), 1)
  assert_true(is_clear(plan.violations))
  assert_true(has_hazard_kind(plan.violations, HazardPlanningOnly))
  assert_true(
    render_text(plan, cargos).contains("transport approval remains external"),
  )
  assert_true(render_markdown(plan, cargos).contains("DEMO-REVIEW-1"))
  assert_true(plan_to_json(plan).contains("dangerous goods planning only"))
  assert_true(
    render_csv(plan, cargos).contains("dangerous-goods-geometry-only"),
  )
  assert_true(
    render_manifest(plan, cargos).contains(
      "transport approval remains external",
    ),
  )
  assert_true(
    render_svg(plan, unit, 800).contains("dangerous-goods-geometry-only"),
  )
}

///|
test "hazard: known review-required pair needs whole-manifest evidence" {
  let unit = LoadUnit::container_20ft("C")
  let cargos = [acid_cargo("A"), acid_cargo("B")]
  let pairs : Array[HazardPairRule] = [
    {
      a: cargos[0].hazard,
      b: cargos[1].hazard,
      relation: ReviewRequired,
      rule_id: "DEMO-SAME-DECLARATION",
      source: "fictional planning workflow only, no transport rule inferred",
    },
  ]
  let rules = { ..StowRules::default(), hazard_pairs: pairs, }
  assert_eq(pack(unit, cargos, rules).placements.length(), 0)
  let reviewed = {
    ..rules,
    hazard_review: Some(demo_review(unit, cargos, pairs)),
  }
  assert_eq(pack(unit, cargos, reviewed).placements.length(), 2)
  let contradictory = {
    ..reviewed,
    hazard_pairs: [pairs[0], { ..pairs[0], relation: ProhibitSameUnit, }],
  }
  assert_true(
    has_hazard_kind(
      assess_hazards(unit, cargos, contradictory),
      HazardSameUnitForbidden,
    ),
  )
}

///|
test "hazard: review snapshot rejects mutations in cargo unit declarations and rules" {
  let unit = LoadUnit::container_20ft("C")
  let cargos = [acid_cargo("A"), acid_cargo("B")]
  let pairs : Array[HazardPairRule] = [
    {
      a: cargos[0].hazard,
      b: cargos[1].hazard,
      relation: ReviewRequired,
      rule_id: "DEMO-1",
      source: "demo evidence",
    },
  ]
  let review = demo_review(unit, cargos, pairs)
  let rules = {
    ..StowRules::default(),
    hazard_pairs: pairs,
    hazard_review: Some(review),
  }
  assert_true(is_clear(assess_hazards(unit, cargos, rules)))
  cargos[0] = { ..cargos[0], weight_g: 25_000, }
  assert_true(
    has_hazard_kind(assess_hazards(unit, cargos, rules), HazardReviewRequired),
  )
  cargos[0] = acid_cargo("A")
  pairs[0] = { ..pairs[0], source: "changed rule revision", }
  assert_true(
    has_hazard_kind(assess_hazards(unit, cargos, rules), HazardReviewRequired),
  )
  pairs[0] = { ..pairs[0], source: "demo evidence", }
  assert_true(is_clear(assess_hazards(unit, cargos, rules)))
  assert_true(
    has_hazard_kind(
      assess_hazards({ ..unit, id: "DIFFERENT", }, cargos, rules),
      HazardReviewRequired,
    ),
  )
  cargos[0] = cargos[0].with_hazard({
    ..cargos[0].hazard,
    declaration_ref: "SDS-r2",
  })
  assert_true(
    has_hazard_kind(assess_hazards(unit, cargos, rules), HazardRuleUnknown),
  )
}

///|
test "hazard: incomplete or unplaced declarations cannot disappear from verify" {
  let unit = LoadUnit::container_20ft("C")
  let cargo = acid_cargo("A")
  let missing_ref = [cargo.with_hazard(Hazard::new(Corrosive, "UN1789", II))]
  let rules = {
    ..StowRules::default(),
    hazard_review: Some(demo_review(unit, missing_ref, [])),
  }
  assert_false(is_clear(assess_hazards(unit, missing_ref, rules)))
  assert_true(
    has_hazard_kind(
      verify(unit, [cargo], [], StowRules::default()),
      HazardReviewRequired,
    ),
  )
  let bad = [cargo.with_hazard(Hazard::new(None, "UN1789", II))]
  assert_true(has_hazard_kind(verify(unit, bad, [], rules), HazardInputInvalid))
  assert_eq(pack(unit, bad, rules).placements.length(), 0)
  let empty_record = HazardReview::new(unit, [cargo], [], "", "", "")
  assert_false(
    is_clear(
      assess_hazards(unit, [cargo], {
        ..rules,
        hazard_review: Some(empty_record),
      }),
    ),
  )
}

///|
test "hazard: palletize and cartonize do not bypass holds or invent splits" {
  let cargos = [acid_cargo("ACID"), bleach_cargo()]
  let rules = { ..StowRules::default(), hazard_pairs: [acid_bleach_rule()], }
  let unit = LoadUnit::pallet_eur("P")
  assert_eq(palletize(unit, cargos, rules).placements.length(), 0)
  let result = cartonize(
    [CartonSpec::new("BOX", Dimensions::new(1000, 1000, 1000), 100_000, 100)],
    cargos,
    rules,
  )
  assert_eq(result.picks.length(), 0)
  assert_eq(result.unpacked.length(), 2)
}

///|
test "hazard: JSON rejects malformed declarations instead of downgrading to ordinary freight" {
  for
    declaration in [
      "null", "{}", "{\"class\":\"typo\",\"un\":\"UN1789\"}", "{\"class\":8,\"un\":\"UN1789\"}",
      "{\"class\":\"8\"}", "{\"class\":\"8\",\"un\":\"UN17X9\"}", "{\"class\":\"8\",\"un\":1789}",
      "{\"class\":\"8\",\"un\":\"UN0000\"}", "{\"class\":\"8\",\"un\":\"UN1789\",\"group\":\"typo\"}",
      "{\"class\":\"8\",\"un\":\"UN1789\",\"declaration_ref\":false}",
    ] {
    let text = "{\"unit\":{\"type\":\"container_20ft\"},\"items\":[{\"id\":\"A\",\"size\":[100,100,100],\"hazard\":" +
      declaration +
      "}]}"
    assert_true(parse_scenario(text) is Err(_))
  }
}

///|
test "hazard: pair evidence and unique cargo ids are required" {
  let unit = LoadUnit::container_20ft("C")
  let cargos = [acid_cargo("A"), acid_cargo("B")]
  let pairs : Array[HazardPairRule] = [
    {
      a: cargos[0].hazard,
      b: cargos[1].hazard,
      relation: ReviewRequired,
      rule_id: "",
      source: "",
    },
  ]
  let rules = {
    ..StowRules::default(),
    hazard_pairs: pairs,
    hazard_review: Some(demo_review(unit, cargos, pairs)),
  }
  assert_true(
    has_hazard_kind(assess_hazards(unit, cargos, rules), HazardInputInvalid),
  )
  assert_true(
    has_hazard_kind(
      assess_hazards(unit, [cargos[0], cargos[0]], rules),
      DuplicateCargo,
    ),
  )
}

///|
test "hazard: unknown classes and invalid UN numbers remain explicit failures" {
  assert_true(HazardClass::parse("8") == Some(Corrosive))
  assert_true(HazardClass::parse("8.unknown") is None)
  for code in ["", "UN0000", "123", "12345", "un1789", "UN17X9"] {
    assert_false(Hazard::new(Corrosive, code, II).is_valid())
  }
  assert_true(Hazard::new(Corrosive, "UN1789", II).is_valid())
  assert_true(Hazard::new(Corrosive, "1789", II).is_valid())
}
