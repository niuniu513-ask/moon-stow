///|
/// Cargo dimensions along the cargo's own axes: `length` runs along the load
/// unit's X axis, `width` along Y and `height` along Z. Origin is the floor at
/// the load unit's inside rear-left corner.
pub(all) struct Dimensions {
  length : Int32
  width : Int32
  height : Int32
} derive(Eq)

///|
pub fn Dimensions::new(
  length : Int32,
  width : Int32,
  height : Int32,
) -> Dimensions {
  { length, width, height, }
}

///|
pub fn Dimensions::is_positive(self : Dimensions) -> Bool {
  self.length > 0 && self.width > 0 && self.height > 0
}

///|
pub fn Dimensions::volume_mm3(self : Dimensions) -> Int64 {
  volume_mm3(self)
}

///|
/// The six axis aligned orientations of a box. The names list which cargo axis
/// ends up on the load unit's X, Y and Z axis, so `WLH` means "width along X,
/// length along Y, height stays vertical".
pub(all) enum Orientation {
  LWH
  WLH
  LHW
  HLW
  WHL
  HWL
} derive(Eq)

///|
pub fn Orientation::all() -> Array[Orientation] {
  [LWH, WLH, LHW, HLW, WHL, HWL]
}

///|
/// The third letter is the vertical axis: only `LWH`/`WLH` keep the cargo
/// upright, `LHW`/`HLW` lay it on its side, `WHL`/`HWL` stand it on its end.
pub fn Orientation::keeps_upright(self : Orientation) -> Bool {
  match self {
    LWH | WLH => true
    LHW | HLW | WHL | HWL => false
  }
}

///|
pub fn Orientation::label(self : Orientation) -> String {
  match self {
    LWH => "LWH"
    WLH => "WLH"
    LHW => "LHW"
    HLW => "HLW"
    WHL => "WHL"
    HWL => "HWL"
  }
}

///|
/// Apply the orientation to the cargo's own dimensions.
pub fn Dimensions::oriented(
  self : Dimensions,
  orientation : Orientation,
) -> Dimensions {
  match orientation {
    LWH => { length: self.length, width: self.width, height: self.height, }
    WLH => { length: self.width, width: self.length, height: self.height, }
    LHW => { length: self.length, width: self.height, height: self.width, }
    HLW => { length: self.height, width: self.length, height: self.width, }
    WHL => { length: self.width, width: self.height, height: self.length, }
    HWL => { length: self.height, width: self.width, height: self.length, }
  }
}

///|
/// Integer point, always the minimum corner of an axis aligned box here.
pub(all) struct Point3 {
  x : Int32
  y : Int32
  z : Int32
} derive(Eq)

///|
pub fn Point3::new(x : Int32, y : Int32, z : Int32) -> Point3 {
  { x, y, z, }
}

///|
/// Axis aligned box: minimum corner plus extents. Half-open intervals are used
/// everywhere, so two boxes that only share a face do not overlap.
pub(all) struct Aabb {
  min : Point3
  size : Dimensions
} derive(Eq)

///|
pub fn Aabb::new(min : Point3, size : Dimensions) -> Aabb {
  { min, size, }
}

///|
pub fn Aabb::at(x : Int32, y : Int32, z : Int32, size : Dimensions) -> Aabb {
  { min: { x, y, z, }, size, }
}

///|
pub fn Aabb::max_x(self : Aabb) -> Int32 {
  self.min.x + self.size.length
}

///|
pub fn Aabb::max_y(self : Aabb) -> Int32 {
  self.min.y + self.size.width
}

///|
pub fn Aabb::max_z(self : Aabb) -> Int32 {
  self.min.z + self.size.height
}

///|
pub fn Aabb::volume_mm3(self : Aabb) -> Int64 {
  self.size.volume_mm3()
}

///|
/// Strictly positive overlap volume of two boxes. Boxes that only touch faces
/// return 0, which is what lets a stack sit flush on the box below.
pub fn Aabb::overlap_volume(a : Aabb, b : Aabb) -> Int64 {
  let dx = min_i(a.max_x(), b.max_x()) - max_i(a.min.x, b.min.x)
  let dy = min_i(a.max_y(), b.max_y()) - max_i(a.min.y, b.min.y)
  let dz = min_i(a.max_z(), b.max_z()) - max_i(a.min.z, b.min.z)
  if dx <= 0 || dy <= 0 || dz <= 0 {
    return 0L
  }
  dx.to_int64() * dy.to_int64() * dz.to_int64()
}

///|
/// Solid intersection: any positive overlap means the two boxes collide.
pub fn Aabb::intersects(a : Aabb, b : Aabb) -> Bool {
  a.min.x < b.max_x() &&
  b.min.x < a.max_x() &&
  a.min.y < b.max_y() &&
  b.min.y < a.max_y() &&
  a.min.z < b.max_z() &&
  b.min.z < a.max_z()
}

///|
/// Footprint overlap area of two boxes projected on the floor, independent of
/// height. Used for support analysis and for floor-area accounting.
pub fn Aabb::footprint_overlap(a : Aabb, b : Aabb) -> Int32 {
  let dx = min_i(a.max_x(), b.max_x()) - max_i(a.min.x, b.min.x)
  let dy = min_i(a.max_y(), b.max_y()) - max_i(a.min.y, b.min.y)
  if dx <= 0 || dy <= 0 {
    return 0
  }
  dx * dy
}

///|
/// Total supported footprint area: sum of floor-area overlaps with every box
/// whose top face is exactly at `self`'s bottom face, clipped to the footprint.
/// Overlaps are counted once per supporting box, which is exact for boxes that
/// do not interpenetrate.
pub fn Aabb::supported_area(self : Aabb, below : Array[Aabb]) -> Int32 {
  let own = self.size.length * self.size.width
  let mut supported = 0
  for i in 0..<below.length() {
    let other = below[i]
    if other.max_z() == self.min.z {
      supported = supported + self.footprint_overlap(other)
    }
  }
  min_i(supported, own)
}

///|
/// Manhattan distance between the closest faces of two boxes: 0 when they touch
/// or overlap, so hazard separation can be expressed as a clearance.
pub fn Aabb::gap(a : Aabb, b : Aabb) -> Int32 {
  let dx = max_i(0, max_i(b.min.x - a.max_x(), a.min.x - b.max_x()))
  let dy = max_i(0, max_i(b.min.y - a.max_y(), a.min.y - b.max_y()))
  let dz = max_i(0, max_i(b.min.z - a.max_z(), a.min.z - b.max_z()))
  dx + dy + dz
}

///|
pub fn Aabb::center_x(self : Aabb) -> Int32 {
  self.min.x + self.size.length / 2
}

///|
pub fn Aabb::center_y(self : Aabb) -> Int32 {
  self.min.y + self.size.width / 2
}

///|
pub fn Aabb::center_z(self : Aabb) -> Int32 {
  self.min.z + self.size.height / 2
}

///|
/// Fits inside a load unit's usable envelope.
pub fn Aabb::fits_within(self : Aabb, envelope : Dimensions) -> Bool {
  self.min.x >= 0 &&
  self.min.y >= 0 &&
  self.min.z >= 0 &&
  self.max_x() <= envelope.length &&
  self.max_y() <= envelope.width &&
  self.max_z() <= envelope.height
}

///|
test "geometry: face contact is not collision" {
  let a = Aabb::at(0, 0, 0, Dimensions::new(100, 100, 100))
  let b = Aabb::at(100, 0, 0, Dimensions::new(100, 100, 100))
  assert_false(a.intersects(b))
  assert_eq(a.overlap_volume(b), 0L)
  assert_eq(a.gap(b), 0)
}

///|
test "geometry: overlap volume" {
  let a = Aabb::at(0, 0, 0, Dimensions::new(100, 100, 100))
  let b = Aabb::at(50, 50, 50, Dimensions::new(100, 100, 100))
  assert_true(a.intersects(b))
  assert_eq(a.overlap_volume(b), 125_000L)
}

///|
test "geometry: supported area is clipped to footprint" {
  let base = Aabb::at(0, 0, 0, Dimensions::new(1000, 1000, 500))
  let item = Aabb::at(0, 0, 500, Dimensions::new(200, 200, 200))
  assert_eq(item.supported_area([base]), 40_000)
  let floating = Aabb::at(0, 0, 501, Dimensions::new(200, 200, 200))
  assert_eq(floating.supported_area([base]), 0)
}

///|
test "geometry: orientations permute axes" {
  let d = Dimensions::new(600, 400, 300)
  assert_true(d.oriented(LWH) == Dimensions::new(600, 400, 300))
  assert_true(d.oriented(WLH) == Dimensions::new(400, 600, 300))
  assert_true(d.oriented(LHW) == Dimensions::new(600, 300, 400))
  assert_true(d.oriented(HLW) == Dimensions::new(300, 600, 400))
  assert_true(d.oriented(WHL) == Dimensions::new(400, 300, 600))
  assert_true(d.oriented(HWL) == Dimensions::new(300, 400, 600))
}

///|
pub extend Dimensions with Eq::{equal, not_equal}

///|
pub extend Orientation with Eq::{equal, not_equal}

///|
pub extend Point3 with Eq::{equal, not_equal}

///|
pub extend Aabb with Eq::{equal, not_equal}
