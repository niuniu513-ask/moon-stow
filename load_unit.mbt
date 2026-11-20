///|
/// What the cargo is loaded into. The geometry and the limit set are the same
/// for every kind, which is why one packer serves containers, trucks, pallets
/// and air ULDs.
#derive(Eq)
pub(all) enum UnitKind {
  Container
  Truck
  Pallet
  AirUld
}

///|
pub fn UnitKind::label(self : UnitKind) -> String {
  match self {
    Container => "container"
    Truck => "truck"
    Pallet => "pallet"
    AirUld => "air-uld"
  }
}

///|
/// One axle of a road vehicle: distance from the load unit's rear face and the
/// maximum legal load on that axle.
#derive(Eq)
pub(all) struct Axle {
  position_mm : Int32
  max_load_g : Int32
  empty_load_g : Int32
}

///|
pub fn Axle::new(position_mm : Int32, max_load_g : Int32) -> Axle {
  { position_mm, max_load_g, empty_load_g: 0, }
}

///|
pub fn Axle::with_empty_load(self : Axle, grams : Int32) -> Axle {
  { ..self, empty_load_g: grams, }
}

///|
#derive(Eq)
pub(all) struct LoadUnit {
  id : String
  kind : UnitKind
  dims : Dimensions
  max_payload_g : Int32
  tare_g : Int32
  floor_limit_g_per_m2 : Int32
  axles : Array[Axle]
  rear_door_at_origin : Bool
  max_stack_height_mm : Int32
}

///|
/// A 20 foot dry container: 5898 x 2352 x 2393 inside, 28 200 kg payload.
pub fn LoadUnit::container_20ft(id : String) -> LoadUnit {
  {
    id,
    kind: Container,
    dims: Dimensions::new(5898, 2352, 2393),
    max_payload_g: 28_200_000,
    tare_g: 2_300_000,
    floor_limit_g_per_m2: 1_000_000,
    axles: [],
    rear_door_at_origin: true,
    max_stack_height_mm: 2393,
  }
}

///|
/// A 40 foot high cube: 12032 x 2352 x 2698, 26 500 kg payload.
pub fn LoadUnit::container_40hc(id : String) -> LoadUnit {
  {
    id,
    kind: Container,
    dims: Dimensions::new(12_032, 2352, 2698),
    max_payload_g: 26_500_000,
    tare_g: 3_900_000,
    floor_limit_g_per_m2: 1_000_000,
    axles: [],
    rear_door_at_origin: true,
    max_stack_height_mm: 2698,
  }
}

///|
/// A 13.6 m rigid truck body with a two axle rear group; the axle limits are the
/// usual 10 t / 11.5 t pair and are what the load distribution check uses.
pub fn LoadUnit::truck_rigid(id : String) -> LoadUnit {
  {
    id,
    kind: Truck,
    dims: Dimensions::new(13_600, 2450, 2700),
    max_payload_g: 24_000_000,
    tare_g: 12_000_000,
    floor_limit_g_per_m2: 1_200_000,
    axles: [
      Axle::new(1_400, 10_000_000).with_empty_load(4_000_000),
      Axle::new(11_000, 11_500_000).with_empty_load(8_000_000),
    ],
    rear_door_at_origin: true,
    max_stack_height_mm: 2700,
  }
}

///|
/// The two pallet footprints that dominate European and North American trade.
pub fn LoadUnit::pallet_eur(id : String) -> LoadUnit {
  {
    id,
    kind: Pallet,
    dims: Dimensions::new(1200, 800, 1800),
    max_payload_g: 1_000_000,
    tare_g: 25_000,
    floor_limit_g_per_m2: 1_500_000,
    axles: [],
    rear_door_at_origin: true,
    max_stack_height_mm: 1800,
  }
}

///|
pub fn LoadUnit::pallet_iso(id : String) -> LoadUnit {
  {
    id,
    kind: Pallet,
    dims: Dimensions::new(1200, 1000, 1800),
    max_payload_g: 1_000_000,
    tare_g: 25_000,
    floor_limit_g_per_m2: 1_500_000,
    axles: [],
    rear_door_at_origin: true,
    max_stack_height_mm: 1800,
  }
}

///|
/// Usable envelope: the declared inside dimensions, capped by the stacking
/// height limit so a plan never relies on a height the unit does not have.
pub fn LoadUnit::envelope(self : LoadUnit) -> Dimensions {
  {
    length: self.dims.length,
    width: self.dims.width,
    height: min_i(self.dims.height, self.max_stack_height_mm),
  }
}

///|
pub fn LoadUnit::floor_area_m2(self : LoadUnit) -> Double {
  floor_area_mm2(self.dims).to_double() / 1_000_000.0
}

///|
pub fn LoadUnit::with_payload(
  self : LoadUnit,
  max_payload_g : Int32,
) -> LoadUnit {
  { ..self, max_payload_g, }
}

///|
pub fn LoadUnit::with_axles(self : LoadUnit, axles : Array[Axle]) -> LoadUnit {
  { ..self, axles, }
}

///|
/// Legacy name: returns capacity in integer cubic MILLIMETRES, not m3.
/// Prefer `capacity_mm3` for explicit units.
pub fn LoadUnit::capacity_m3(self : LoadUnit) -> Int64 {
  self.envelope().volume_mm3()
}

///|
pub fn LoadUnit::capacity_mm3(self : LoadUnit) -> Int64 {
  self.envelope().volume_mm3()
}

///|
test "load unit: 20ft envelope" {
  let u = LoadUnit::container_20ft("C1")
  assert_eq(u.envelope().height, 2393)
  assert_eq(u.kind.label(), "container")
  assert_true(u.capacity_m3() > 30_000_000_000L)
}

///|
test "load unit: truck axles are carried through" {
  let u = LoadUnit::truck_rigid("T1")
  assert_eq(u.axles.length(), 2)
  assert_eq(u.axles[1].max_load_g, 11_500_000)
}

///|
pub extend UnitKind with Eq::{equal, not_equal}

///|
pub extend Axle with Eq::{equal, not_equal}

///|
pub extend LoadUnit with Eq::{equal, not_equal}
