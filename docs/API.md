# moon-stow API 速查

本文件按模块给出对外接口。完整签名以 `pkg.generated.mbti`（`moon info` 生成）为准，
这里只列调用者最常用的部分，并给出"什么时候该用哪一个"。

长度单位一律毫米（`Int32`），重量单位一律克（`Int32`），体积单位 mm³（`Int64`）。
没有任何浮点数参与几何判定，同一个输入在任何平台得到同一份装载图。

## 载具 load_unit.mbt

```moonbit
pub fn LoadUnit::container_20ft(id : String) -> LoadUnit
pub fn LoadUnit::container_40hc(id : String) -> LoadUnit
pub fn LoadUnit::truck_rigid(id : String) -> LoadUnit
pub fn LoadUnit::pallet_eur(id : String) -> LoadUnit
pub fn LoadUnit::pallet_iso(id : String) -> LoadUnit
pub fn LoadUnit::with_payload(Self, Int32) -> Self
pub fn LoadUnit::with_axles(Self, Array[Axle]) -> Self
pub fn LoadUnit::capacity_m3(Self) -> Int64
pub fn LoadUnit::floor_area_m2(Self) -> Double
```

内置载具的内尺寸取自 ISO 668、EN 13698-1 与 ISO 6780：20ft 5898×2352×2393、
40HC 12032×2352×2698、9.6 m 厢式货车 9600×2450×2700、EUR 托盘 1200×800、
ISO 托盘 1200×1000。`rear_door_at_origin` 记录门在 x=0 端还是远端，多站点场景靠它
决定"先送的货靠门"。

## 几何 geometry.mbt

```moonbit
pub fn Dimensions::new(length : Int32, width : Int32, height : Int32) -> Dimensions
pub fn Dimensions::oriented(Self, Orientation) -> Dimensions
pub fn Dimensions::volume_mm3(Self) -> Int64
pub fn Aabb::at(x : Int32, y : Int32, z : Int32, size : Dimensions) -> Aabb
pub fn Aabb::intersects(Self, Self) -> Bool
pub fn Aabb::gap(Self, Self) -> Int32
pub fn Aabb::supported_area(Self, Array[Self]) -> Int32
pub fn Orientation::all() -> Array[Orientation]
```

`Orientation` 是六个离散朝向（LWH/WLH/…），`gap` 返回两个盒子之间最近的距离，
不重叠时为 0；危险品净距与 `min_gap_mm` 都建立在它上面。

## 货物 cargo.mbt

```moonbit
pub fn Cargo::new(id : String, dims : Dimensions, weight_g : Int32) -> Cargo
pub fn Cargo::with_upright(Self, UprightPolicy) -> Self
pub fn Cargo::with_stack_limit(Self, layers : Int32, top_g : Int32) -> Self
pub fn Cargo::with_hazard(Self, Hazard) -> Self
pub fn Cargo::with_stop(Self, Int32) -> Self
pub fn Cargo::with_priority(Self, Int32) -> Self
pub fn Cargo::with_group(Self, String) -> Self
pub fn Cargo::with_gap(Self, Int32) -> Self
pub fn Cargo::fragile_item(Self) -> Self
pub fn Cargo::sort_key(Self) -> String
```

`with_upright(KeepUpright)` 只允许竖放朝向；`fragile_item()` 等价于"顶上不许压任何东西"；
`with_gap()` 是这一件四周要留的空隙，用于留通风道或便于人工搬运。

## 规则 rules.mbt

```moonbit
pub fn StowRules::default() -> StowRules
pub fn StowRules::with_support(Self, permille : Int32) -> Self   // 默认 700‰
pub fn StowRules::with_cog_margin(Self, permille : Int32) -> Self // 默认 600‰
pub fn StowRules::with_layer_cap(Self, layers : Int32) -> Self
pub fn StowRules::clearance(Self, level : Int32) -> Int32
```

`with_support` 控制"底面积至少有多少比例被支撑"，`with_cog_margin` 控制重心允许偏离
地板中心的比例。两个值都写成千分比，避免浮点比较。

## 危险品 hazard.mbt

```moonbit
pub fn HazardClass::parse(text : String) -> HazardClass
pub fn Hazard::new(class : HazardClass, un : String, group : PackingGroup) -> Hazard
pub fn segregation_level(a : HazardClass, b : HazardClass) -> Int32
pub fn clearance_for_level(level : Int32) -> Int32
pub fn segregation_label(level : Int32) -> String
```

16×16 隔离表按 IMDG 7.2.4 的形态压缩成 0–4 五级，对应净距 0/3/6/12/24 m。
爆炸品一行一律给 4 级（24 m），这是有意保守：宁可把货留在箱外，也不给一个
"看起来合规"的错误答案。需要按航线细化时用 `StowRules::clearance` 覆盖某一级的毫米数。

## 装箱 pack.mbt

```moonbit
pub fn pack(unit : LoadUnit, cargos : Array[Cargo], rules : StowRules) -> LoadPlan
pub fn pack_all(unit : LoadUnit, cargos : Array[Cargo], rules : StowRules) -> LoadPlan?
pub fn pack_ordered(unit : LoadUnit, cargos : Array[Cargo], rules : StowRules, order : Array[Int32]) -> LoadPlan
pub fn order_cargos(cargos : Array[Cargo]) -> Array[Int32]
```

`pack` 是极值点启发式：每放一件货，就在它身上生成三个候选角点（沿 x、沿 y、往上），
评分顺序是 低 z → 高支撑面积 → 小 x → 小 y。`order_cargos` 决定先放谁：
重而大、限制多的先放。`pack_all` 在返回前跑一次配平，`pack_ordered` 供调用方自己
安排顺序（例如按站点倒序）。

## 托盘码垛 palletize.mbt

```moonbit
pub fn palletize(unit : LoadUnit, cargos : Array[Cargo], rules : StowRules) -> LoadPlan
pub fn order_by_footprint(cargos : Array[Cargo]) -> Array[Int32]
```

按层推进：一层先沿 x 排行、行满换 y，层满往上。适合箱规一致的码垛；
混规或需要贴合凹槽时用 `pack`。两者返回同一个 `LoadPlan` 类型，可以并排比较。

## 选箱 cartonize.mbt

```moonbit
pub fn cartonize(catalog : Array[CartonSpec], goods : Array[Cargo], rules : StowRules) -> Cartonization
pub fn volumetric_weight_g(dims : Dimensions) -> Int32
pub fn chargeable_weight_g(spec : CartonSpec, goods_weight_g : Int32) -> Int32
```

对每个纸箱规格各跑一次 `pack`，先比"装得下的件数"，再比运费（计费重 = max(实重,
体积重)，体积重按 1 kg : 5000 cm³），最后比 id，保证同输入同结果。

## 校验 verify.mbt

```moonbit
pub fn verify(unit : LoadUnit, cargos : Array[Cargo], placements : Array[Placement], rules : StowRules) -> Array[Violation]
pub fn is_clear(violations : Array[Violation]) -> Bool
pub fn count_by_severity(violations : Array[Violation], severity : Severity) -> Int32
```

八组检查：身份重复、几何越界与朝向、碰撞、支撑与堆叠顶载、载重与地板点载荷、
轴荷与重心、危险品净距、后装先卸（overstow）。校验不依赖装箱器，手工写出的
`placements` 一样能查。

## 稳定性 stability.mbt

```moonbit
pub fn axle_loads(unit : LoadUnit, placements : Array[Placement], cargos : Array[Cargo]) -> Array[Int32]
pub fn max_floor_pressure(placements : Array[Placement], cargos : Array[Cargo]) -> Int32
pub fn cog_offset_permille(cog : Point3, envelope : Dimensions) -> (Int32, Int32)
pub fn center_of_gravity(placements : Array[Placement], cargos : Array[Cargo]) -> Point3?
pub fn balance_shift(unit : LoadUnit, placements : Array[Placement], cargos : Array[Cargo]) -> (Int32, Int32)
pub fn balance_load(unit : LoadUnit, placements : Array[Placement], cargos : Array[Cargo]) -> Array[Placement]
```

`balance_load` 只做一次整体平移：货车把重心挪到轴距中点，集装箱与托盘挪到地板中心；
挪完仍然越界的，交给 `verify` 报出来，而不是悄悄夹紧。

## 报告 report.mbt / svg.mbt

```moonbit
pub fn render_text(plan : LoadPlan, cargos : Array[Cargo]) -> String
pub fn render_markdown(plan : LoadPlan, cargos : Array[Cargo]) -> String
pub fn render_csv(plan : LoadPlan, cargos : Array[Cargo]) -> String
pub fn render_manifest(plan : LoadPlan, cargos : Array[Cargo]) -> String
pub fn render_svg(plan : LoadPlan, unit : LoadUnit, width_px : Int32) -> String
pub fn render_top_view(plan : LoadPlan, unit : LoadUnit, width_px : Int32) -> String
pub fn render_side_view(plan : LoadPlan, unit : LoadUnit, width_px : Int32) -> String
pub fn plan_to_json(plan : LoadPlan) -> String
pub fn summary_line(plan : LoadPlan) -> String
```

文本报告给人看，CSV 进表格，`render_manifest` 是装车/理货清单，SVG 直接进浏览器或
贴进文档（不依赖任何绘图库，纯字符串拼接）。

## 作业单 scenario.mbt

```moonbit
pub fn parse_scenario(text : String) -> Result[Scenario, String]
```

把一个 JSON 作业单解析成 `LoadUnit` + `Array[Cargo]` + `StowRules`，格式见
[JOB-FORMAT.md](JOB-FORMAT.md)。错误一律返回可读的字符串（缺字段、尺寸非正、未知载具），
不做隐式兜底。
