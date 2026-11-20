# moon-stow API 速查

本文件按模块给出对外接口。完整签名以 `pkg.generated.mbti`（`moon info` 生成）为准，
这里只列调用者最常用的部分，并给出"什么时候该用哪一个"。

长度单位一律毫米（`Int32`），重量单位一律克（`Int32`），体积单位 mm³（`Int64`）。
几何判定使用整数；当前复测目标为 Wasm、WasmGC 与 JavaScript，Native 另见验证记录。

## 载具 load_unit.mbt

```moonbit
pub fn LoadUnit::container_20ft(id : String) -> LoadUnit
pub fn LoadUnit::container_40hc(id : String) -> LoadUnit
pub fn LoadUnit::truck_rigid(id : String) -> LoadUnit
pub fn LoadUnit::pallet_eur(id : String) -> LoadUnit
pub fn LoadUnit::pallet_iso(id : String) -> LoadUnit
pub fn LoadUnit::with_payload(Self, Int32) -> Self
pub fn LoadUnit::with_axles(Self, Array[Axle]) -> Self
pub fn LoadUnit::capacity_mm3(Self) -> Int64
pub fn LoadUnit::capacity_m3(Self) -> Int64 // 旧名，返回值仍是 mm³
pub fn LoadUnit::floor_area_m2(Self) -> Double
```

内置值是可替换的演示配置，不是标准或设备认证：20ft 内包络 5898×2352×2393 mm，
40HC 12032×2352×2698 mm；货车长 13600 mm（并非 9.6 m）；EUR/ISO 托盘底面为1200×800/1200×1000 mm。
ULD 示例仅为矩形包络，未建模真实航空集装器轮廓，不能标作 LD3。
`capacity_mm3` 返回立方毫米；历史 `capacity_m3` 名称有误，但为兼容保留同样返回值。
`rear_door_at_origin=false` 使用远端车门进行越站校验；启发式可能返回带越站诊断的未完成方案。
`Axle.empty_load_g` 为用户提供的空载轴荷，所有空载轴荷之和须等于载具 `tare_g`。
`Axle::new` 默认空载轴荷为0，可用 `with_empty_load` 设置；默认货车的4t/8t只是演示，不是实际称重。

## 几何 geometry.mbt

```moonbit
pub fn Dimensions::new(length : Int32, width : Int32, height : Int32) -> Dimensions
pub fn Dimensions::oriented(Self, Orientation) -> Dimensions
pub fn Dimensions::volume_mm3(Self) -> Int64
pub fn Aabb::at(x : Int32, y : Int32, z : Int32, size : Dimensions) -> Aabb
pub fn Aabb::intersects(Self, Self) -> Bool
pub fn Aabb::gap(Self, Self) -> Int32
pub fn Aabb::side_gap(Self, Self) -> Int32
pub fn Aabb::shares_height(Self, Self) -> Bool
pub fn Aabb::supported_area(Self, Array[Self]) -> Int32
pub fn Orientation::all() -> Array[Orientation]
```

`Orientation` 是六个离散朝向（LWH/WLH/…）。`gap` 是三轴曼哈顿距离，接触或重叠时为 0，
只用于几何查询；`side_gap` 只算 x+y，`shares_height` 判断两盒是否落在同一高度带。
声明净距（`with_gap`）判定用后两者的组合：共享高度带才比较侧向净距，堆叠不受限。
两者都不代表 IMDG 隔离距离。

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
`with_gap()` 是对"同一高度带上并列"两件货物的最小侧向（x+y）净距，取两件声明值较大者；
堆叠时两者只是上下接触、不共享高度带，因此声明净距不阻止堆码，包装箱也不会被抬离支撑面。
这是纯几何参数，不保证通风、消防或 IMDG 类隔离。

## 规则 rules.mbt

```moonbit
pub fn StowRules::default() -> StowRules
pub fn StowRules::with_support(Self, permille : Int32) -> Self   // 默认 700‰
pub fn StowRules::with_cog_margin(Self, permille : Int32) -> Self // 默认 600‰
pub fn StowRules::with_layer_cap(Self, layers : Int32) -> Self
```

`with_support` 控制"底面积至少有多少比例被支撑"，`with_cog_margin` 控制重心允许偏离
地板中心的比例。两个值都写成千分比，避免浮点比较。

## 危险品 hazard.mbt

```moonbit
pub fn HazardClass::parse(text : String) -> HazardClass?
pub fn Hazard::new(class : HazardClass, un : String, group : PackingGroup) -> Hazard
pub fn Hazard::with_declaration(Self, reference : String) -> Hazard
pub fn HazardReview::new(LoadUnit, Array[Cargo], Array[HazardPairRule], String, String, String) -> HazardReview
pub fn assess_hazards(LoadUnit, Array[Cargo], StowRules) -> Array[Violation]
pub fn planning_scope(LoadPlan) -> String
```

`HazardPairRule` 按完整 `Hazard` 值双向匹配，包含声明版本引用；`relation` 为
`ProhibitSameUnit`（禁止同载具）或 `ReviewRequired`（具备规则后仍须人工复核）。
`rule_id` 和 `source` 必须非空；默认无任何组合规则。多条匹配规则均检查，禁配不被覆盖。
涉及任一危险品的所有货物组合（含与普通货的组合、同种货）都必须有具体规则。

`StowRules.hazard_pairs` 接收规则；`hazard_review` 接收整单复核记录。
构造复核记录的后三个字符串为记录编号、复核人和外部证据/运输条件引用，均须非空。
记录复制完整货单、载具与规则快照，后续改变任一快照内容都会使复核失效。
外部条件（航线、船舶、开闭式 CTU、包装、数量、温控等）的核查与真实性由外部人员负责。

未知关系、无效输入或缺少/失效复核一律是 `Error`。审核记录不能覆盖禁配或未知关系。
即使只有一件危险品也要求声明引用和整单复核；成功仅为 `HazardPlanningOnly` 警示下的几何规划。
`is_clear` 仅表示没有 `Error`，`pack_all` 的 `Some` 仅表示整单几何完成，均不是运输许可。
`cartonize` 不对危险品自动分箱。JSON 作业单不支持导入复核凭据，解析成功仍默认阻断危险品。
旧 `segregation_level` / `clearance_for_level` / `segregation_label` 和距离覆盖 API 已删除。
`HazardClass::parse` 对未知值返回可选值 `None`，不把拼错类别改成普通货。
详见 [HAZARD-REVIEW.md](HAZARD-REVIEW.md)。

## 装箱 pack.mbt

```moonbit
pub fn pack(unit : LoadUnit, cargos : Array[Cargo], rules : StowRules) -> LoadPlan
pub fn pack_all(unit : LoadUnit, cargos : Array[Cargo], rules : StowRules) -> LoadPlan?
pub fn pack_ordered(unit : LoadUnit, cargos : Array[Cargo], rules : StowRules, order : Array[Int32]) -> LoadPlan
pub fn order_cargos(cargos : Array[Cargo]) -> Array[Int32]
```

`pack` 是极值点启发式：每放一件货，就在它身上生成三个候选角点（沿 x、沿 y、往上），
评分顺序是 低 z → 高支撑面积 → 小 x → 小 y。`order_cargos` 决定先放谁：
站点小的、优先级高的、重量大的、体积大的先放，最后按id排序。`pack_all` 在返回前跑一次配平，`pack_ordered` 供调用方自己
安排顺序；重复索引不重复装货，省略的货物进入unplaced，非法索引被跳过。

## 托盘码垛 palletize.mbt

```moonbit
pub fn palletize(unit : LoadUnit, cargos : Array[Cargo], rules : StowRules) -> LoadPlan
pub fn order_by_footprint(cargos : Array[Cargo]) -> Array[Int32]
```

两段式：地面先按货架排布（沿 x 排行、行满换 y），然后逐列往上摞——每件只允许
落在能完整托住它底面的那一件上，所以支撑关系始终是一棵干净的柱状树，人工复核时
一眼能看出谁压着谁。适合箱规一致的码垛；要贴合凹槽、钻空位时用 `pack`。两者返回
同一个 `LoadPlan` 类型，可以并排比较。

## 选箱 cartonize.mbt

```moonbit
pub fn cartonize(catalog : Array[CartonSpec], goods : Array[Cargo], rules : StowRules) -> Cartonization
pub fn volumetric_weight_g(dims : Dimensions) -> Int32
pub fn chargeable_weight_g(spec : CartonSpec, goods_weight_g : Int32) -> Int32
```

对每个纸箱规格按体积降序尝试加入货物，单件不合适时继续尝试其他货物；比较可装件数、
箱材成本 `cost_cents`，最后比 id。结果的 `cargo_index` 指向原始 `goods`，不是子单下标。
计费重API单独提供，未参与箱型排序，也没有承运人运费模型；体积重按1kg:5000cm³向上取整到克。

## 校验 verify.mbt

```moonbit
pub fn verify(unit : LoadUnit, cargos : Array[Cargo], placements : Array[Placement], rules : StowRules) -> Array[Violation]
pub fn is_clear(violations : Array[Violation]) -> Bool
pub fn count_by_severity(violations : Array[Violation], severity : Severity) -> Int32
```

八组检查：身份重复、几何越界与朝向、碰撞、支撑与堆叠顶载、载重与地板点载荷、
轴荷与重心、危险品整单复核、后装先卸（overstow）。校验不依赖装箱器，手工写出的
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

## 数值、静力模型与完整性边界

`validate_input` 拒绝非正或大于30000mm的边、负重量、无效规则、重复货号（由整单检查报告）、
超过1000件或累计质量（含空载轴荷）大于2e9g、累计体积大于8e15mm³的规划作业。
底面积为Int32，支撑率和轴荷力矩使用Int64中间值。选箱的单箱体积上限8e12mm³，总箱成本上限2e9分。

顶载沿支撑图传播全部上层重量；跨多个底座的桥接货物，对每个可达底座都计入全部重量，
是保守上界，不是弹性/接触力求解。地板压力包含经此图传递的载荷，不能替代真实接触点载荷测算。
轴荷包括已声明的空载轴荷；轴距外货物全部归最近轴，未求解悬挑反力或动态载荷。
默认货车的“有效载荷24t”和“空载12t”均为测试参数，不是36t总重的法定许可。

自动规划先剪枝再最终verify，轴荷等整车条件可能在最终检查报错；不能宣称自动输出一定无错误。
缺货是Error，`is_clear`不接受缺货布局；不完整规划仍可查看unplaced与诊断。
必须同时检查 `unplaced`、`violations` 与 `planning_scope`；几何完成不等于现场装载或运输许可。
