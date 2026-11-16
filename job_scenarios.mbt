///|
/// The job file printed in docs/JOB-FORMAT.md has to stay parseable. These tests
/// are the contract behind that document: if a field is renamed, the doc and the
/// tests have to move together.
test "job: the documented job file parses back to the same scenario" {
  let text =
    #|{
    #|  "unit": { "type": "container_40hc", "id": "MSKU7654321" },
    #|  "items": [
    #|    {
    #|      "id": "PLT-A01",
    #|      "size": [1200, 800, 1450],
    #|      "weight_kg": 420,
    #|      "upright": "keep_upright",
    #|      "stop": 1,
    #|      "priority": 5,
    #|      "gap_mm": 50,
    #|      "group": "pallet",
    #|      "stackable": false
    #|    },
    #|    {
    #|      "id": "CTN-B07",
    #|      "size": [600, 400, 350],
    #|      "weight_kg": 18,
    #|      "upright": "free",
    #|      "stop": 2,
    #|      "max_layers": 4,
    #|      "top_load_kg": 60,
    #|      "fragile": false,
    #|      "hazard": { "class": "3", "un": "UN1263", "group": "II" }
    #|    }
    #|  ],
    #|  "rules": {
    #|    "min_support_permille": 650,
    #|    "cog_margin_permille": 500,
    #|    "max_stack_layers": 4,
    #|    "overstow": true,
    #|    "axles": false
    #|  }
    #|}
  let scenario = match parse_scenario(text) {
    Ok(s) => s
    Err(message) => fail("expected a valid job, got: " + message)
  }
  assert_eq(scenario.unit.id, "MSKU7654321")
  assert_eq(scenario.unit.dims.height, 2698)
  assert_eq(scenario.cargos.length(), 2)
  let pallet = scenario.cargos[0]
  assert_eq(pallet.id, "PLT-A01")
  assert_eq(pallet.weight_g, 420_000)
  assert_eq(pallet.dims.length, 1200)
  assert_eq(pallet.stop, 1)
  assert_eq(pallet.priority, 5)
  assert_eq(pallet.min_gap_mm, 50)
  assert_eq(pallet.group, "pallet")
  assert_eq(pallet.max_stack_layers, 1)
  assert_eq(pallet.max_top_load_g, 0)
  let carton = scenario.cargos[1]
  assert_eq(carton.max_stack_layers, 4)
  assert_eq(carton.max_top_load_g, 60_000)
  assert_eq(carton.hazard.un_number, "UN1263")
  assert_true(carton.hazard.class == FlammableLiquid)
  assert_true(carton.hazard.packing_group == II)
  assert_eq(scenario.rules.min_support_permille, 650)
  assert_eq(scenario.rules.cog_margin_permille, 500)
  assert_eq(scenario.rules.max_stack_layers, 4)
  assert_eq(scenario.rules.enforce_overstow, true)
  assert_eq(scenario.rules.enforce_axles, false)
}

///|
test "job: missing unit and unknown unit type are reported, not defaulted" {
  match parse_scenario("{\"items\": []}") {
    Ok(_) => fail("a job without a unit must fail")
    Err(message) => assert_eq(message, "missing \"unit\"")
  }
  let unknown = "{\"unit\": { \"type\": \"container_53ft\" }, \"items\": []}"
  match parse_scenario(unknown) {
    Ok(_) => fail("an unknown unit type must fail")
    Err(message) =>
      assert_eq(message, "unit: unknown or incomplete unit description")
  }
}

///|
test "job: a bad item points at its own index" {
  let text =
    #|{
    #|  "unit": { "type": "pallet_eur" },
    #|  "items": [
    #|    { "id": "OK", "size": [400, 300, 250], "weight_kg": 12 },
    #|    { "id": "BAD", "size": [400, -300, 250], "weight_kg": 12 }
    #|  ]
    #|}
  match parse_scenario(text) {
    Ok(_) => fail("a negative size must fail")
    Err(message) => assert_eq(message, "items[1]: incomplete item")
  }
}

///|
test "job: rules are optional and fall back to the documented defaults" {
  let text =
    #|{
    #|  "unit": { "type": "container_20ft" },
    #|  "items": [{ "id": "A", "size": [1000, 1000, 1000], "weight_kg": 100 }]
    #|}
  let scenario = match parse_scenario(text) {
    Ok(s) => s
    Err(message) => fail("expected defaults to parse, got: " + message)
  }
  assert_eq(scenario.unit.id, "container_20ft")
  assert_eq(scenario.rules.min_support_permille, 700)
  assert_eq(scenario.rules.cog_margin_permille, 600)
  assert_eq(scenario.rules.enforce_overstow, true)
  assert_eq(scenario.rules.enforce_axles, true)
  assert_eq(scenario.cargos[0].weight_g, 100_000)
}

///|
test "job: the documented file can be packed and verified end to end" {
  let text =
    #|{
    #|  "unit": { "type": "container_40hc", "id": "MSKU7654321" },
    #|  "items": [
    #|    { "id": "PLT-A01", "size": [1200, 800, 1450], "weight_kg": 420, "stackable": false },
    #|    { "id": "CTN-B07", "size": [600, 400, 350], "weight_kg": 18, "stop": 2 }
    #|  ]
    #|}
  let scenario = match parse_scenario(text) {
    Ok(s) => s
    Err(message) => fail("expected a valid job, got: " + message)
  }
  let plan = pack(scenario.unit, scenario.cargos, scenario.rules)
  assert_eq(plan.unplaced.length(), 0)
  let findings = verify(
    scenario.unit,
    scenario.cargos,
    plan.placements,
    scenario.rules,
  )
  assert_eq(is_clear(findings), true)
  assert_true(render_text(plan, scenario.cargos).contains("PLT-A01"))
}
