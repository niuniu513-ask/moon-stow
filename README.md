# moon-stow

用 MoonBit 写的确定性三维装载与配载引擎：集装箱配载、托盘码垛、电商选箱、多站点装车，
全部用整数毫米计算，输出可复核的装载计划、逐项规则报告、JSON 装载单和 SVG 示意图。

装载计划不是"能塞进去就行"。真实现场有六类硬约束：不能悬空、不能压坏、不能超重、
不能偏心、危险品必须隔离、后送的货不能挡前送的货。moon-stow 把这些约束写成可测试的
规则，再由同一个校验器同时为自动计划和人工调整过的计划打分，所以算法与审核用同一把尺子。

## 快速开始

从源码使用（克隆后把示例放进自己的模块）：

```bash
git clone https://github.com/niuniu513-ask/moon-stow
cd moon-stow
moon run examples/quickstart
```

在自己的模块里引用：在 `moon.pkg` 的 `import` 中加入 `"niuniu513-ask/moon-stow"`，
依赖通过 Git 或 Mooncakes 拉取，模块名与 `moon.mod` 一致。

```moonbit
fn main {
  let unit = @moon-stow.LoadUnit::container_20ft("MSKU1234567")
  let cargos = [
    @moon-stow.Cargo::new("TV-55", @moon-stow.Dimensions::new(1350, 850, 780), 22_000),
    @moon-stow.Cargo::new("DESK", @moon-stow.Dimensions::new(1600, 900, 300), 34_000)
      .fragile_item()
      .with_upright(@moon-stow.Fixed),
    @moon-stow.Cargo::new("CHAIR", @moon-stow.Dimensions::new(700, 700, 950), 8_000),
  ]
  let plan = @moon-stow.pack(unit, cargos, @moon-stow.StowRules::default())
  println(@moon-stow.render_text(plan, cargos))
  println(@moon-stow.summary_line(plan))
}
```

输出（节选，注意货物被整体滑到地板中央，重心落到箱体中心）：

```text
LOAD PLAN MSKU1234567 (container)
------------------------------------------------------------
pieces      3 of 3
volume      1.792 of 33.195 (5.4%)
weight      64.000 kg of 28.2 t (0.2%)
floor       3.077 m2 footprint, stack 0.95 m
centre      x 2.94 m, y 1.03 m, z 0.27 m

  #  cargo            stop layer orient  x         y         z         size                 kg
  1  DESK                0     1 LWH     2228      102       0         1600x900x300         34.000 kg
  2  TV-55               0     1 WLH     2228      1002      0         850x1350x780         22.000 kg
  3  CHAIR               0     1 WLH     3078      1002      0         700x700x950          8.000 kg
```

## 能做什么

| 模块 | 内容 |
|---|---|
| `geometry.mbt` | 整数毫米几何：尺寸、六种朝向、包围盒、体积交叠、支撑面积、曼哈顿间距 |
| `units.mbt` | 单位换算与人类可读格式化（m³、kg/t、百分比、米） |
| `hazard.mbt` | 16 类危险品、包装类别、16×16 隔离等级表、分级净距（0/3/6/12/24 m） |
| `load_unit.mbt` | 20ft/40HC 集装箱、厢式货车（含双轴载荷上限）、欧标/ISO 托盘、空运 ULD |
| `cargo.mbt` | 货物属性：重量、朝向策略、可堆码层数、顶载上限、易碎、危险品、站点、优先级、间距 |
| `rules.mbt` | 装载规则：最小支撑率、重心偏移带、层数上限、隔离等级启用、越站禁令、轴荷校验 |
| `plan.mbt` | 装载计划数据结构与指标：体积率、重量率、地板占用、重心、堆高、分站重量 |
| `stability.mbt` | 轴荷杠杆分配、地板点载荷、重心偏移、装车后整体归位（货车按轴距中点、集装箱按地板中心） |
| `verify.mbt` | 八组校验：身份、几何朝向、碰撞、支撑/层数/顶载、载重/地板、轴荷/重心、危险品净距、越站 |
| `pack.mbt` | 极值点启发式装箱器，带完整约束裁剪、确定性排序、可插拔装载顺序、装箱后自动配平 |
| `palletize.mbt` | 货架式分层码垛（行/层推进，层高取层内最高件） |
| `cartonize.mbt` | 电商选箱：体积重、计费重、按件数与成本择优、空隙率 |
| `report.mbt` | 文本报告、Markdown 报告、CSV 装载单、分站送货清单 |
| `svg.mbt` | 俯视图 / 侧视图 / 合并 SVG 图纸，按站点着色 |
| `scenario.mbt` | JSON 作业单解析、装载计划 JSON 序列化（稳定字段顺序，便于 CI 比对） |

## 三个使用场景

### 1. 集装箱配载与危险品隔离

```moonbit
let unit = @moon-stow.LoadUnit::container_20ft("C1")
let cargos = [
  @moon-stow.Cargo::new("EXPL", @moon-stow.Dimensions::new(800, 600, 600), 10_000)
    .with_hazard(@moon-stow.Hazard::new(@moon-stow.Explosive, "0004", @moon-stow.II)),
  @moon-stow.Cargo::new("OXI", @moon-stow.Dimensions::new(800, 600, 600), 10_000)
    .with_hazard(@moon-stow.Hazard::new(@moon-stow.Oxidizer, "1479", @moon-stow.II)),
]
let plan = @moon-stow.pack(unit, cargos, @moon-stow.StowRules::default())
// 1.1 类与氧化剂要求 3 m 净距，箱宽只有 2.352 m，第二件必然装不进去，
// 计划里的 unplaced 会写明原因，而不是把两件塞在一起当没看见。
```

### 2. 托盘码垛

```moonbit
let unit = @moon-stow.LoadUnit::pallet_eur("EUR-01")
let cargos : Array[@moon-stow.Cargo] = []
for i in 0..<12 {
  cargos.push(@moon-stow.Cargo::new("CTN-" + i.to_string(),
    @moon-stow.Dimensions::new(400, 300, 250), 7_000))
}
let plan = @moon-stow.palletize(unit, cargos, @moon-stow.StowRules::default())
```

### 3. 电商选箱

```moonbit
let catalog = [
  @moon-stow.CartonSpec::new("S", @moon-stow.Dimensions::new(350, 250, 200), 8_000, 70),
  @moon-stow.CartonSpec::new("M", @moon-stow.Dimensions::new(450, 350, 300), 15_000, 110),
  @moon-stow.CartonSpec::new("L", @moon-stow.Dimensions::new(600, 450, 400), 25_000, 165),
]
let goods = [
  @moon-stow.Cargo::new("MUG", @moon-stow.Dimensions::new(120, 120, 110), 400),
  @moon-stow.Cargo::new("BOOK", @moon-stow.Dimensions::new(240, 170, 40), 700),
]
let result = @moon-stow.cartonize(catalog, goods, @moon-stow.StowRules::default())
println(result.total_cost_cents.to_string())      // 总箱成本（分）
println(@moon-stow.format_pct(result.void_fill_permille))  // 空隙率
```

## 作业单（JSON）

```json
{
  "unit": { "type": "truck_rigid", "id": "TRK-77" },
  "items": [
    { "id": "PAL-A", "size": [1200, 800, 1200], "weight_kg": 180, "stop": 0 },
    { "id": "PAL-C", "size": [1200, 1000, 1400], "weight_kg": 220, "stop": 1 },
    { "id": "GLASS", "size": [1600, 800, 60], "weight_kg": 90, "fragile": true, "upright": "fixed" }
  ],
  "rules": { "min_support_permille": 800, "cog_margin_permille": 500 }
}
```

```moonbit
match @moon-stow.parse_scenario(text) {
  Ok(scenario) => {
    let plan = @moon-stow.pack(scenario.unit, scenario.cargos, scenario.rules)
    println(@moon-stow.render_manifest(plan, scenario.cargos))
    println(@moon-stow.plan_to_string(plan))
  }
  Err(message) => println("bad job file: " + message)
}
```

## 运行示例

```bash
moon run examples/quickstart   # 集装箱装箱 + 文本报告
moon run examples/pallet       # 托盘码垛 vs 通用装箱对比
moon run examples/cartonize    # 选箱与成本
moon run examples/multistop    # 多站点装车 + 送货清单 + JSON + SVG
moon run examples/hazard       # 危险品隔离：净距放不下时谁被留在箱外
```

## 校验

```bash
moon check --deny-warn
moon test
moon fmt --check
```

`moon test` 覆盖：几何交叠与支撑面积、六朝向、危险品隔离表对称性、边界与碰撞、支撑率与层数、
顶载与易碎、载重与地板点载荷、轴荷分配、重心带、越站顺序、确定性（两次运行同布局）、
JSON 解析与序列化、报告与 SVG 结构。

## 设计取舍

- **整数毫米**：所有坐标、体积、重量都用整数，避开浮点误差导致的"差 1 mm 判碰撞"问题；
  体积用 `Int64` mm³，格式化时才转成 m³。
- **校验器与装箱器共用同一套几何与规则**：自动计划与人工调整的计划用完全相同的判定，
  不会出现"算法过、人工过不了"的情况。
- **确定性优先**：排序键带 id 兜底，同样输入永远得到同样布局，便于 CI 比对与现场复现。
- **失败要说明原因**：装不进去的货进 `unplaced` 并附原因，不静默丢弃。
- **装完自动配平**：极值点启发式总是从门口角落往里长，重心天然偏前；装箱结束后整批货一起平移，
  让重心落到平衡点上——货车按轴距中点（重量压在轮子之间），集装箱与托盘按地板中心——
  平移被限制在自由空间内，所以贴墙的货只会往回移，不会穿墙。平移不改变相对几何，
  支撑、堆码、隔离和越站的判定结果完全不变。

## 与已有工作的区别

Mooncakes 与 GitHub 上的 MoonBit 装箱类模块目前都是**二维**矩形布局/纹理图集
（如 `moon_binpack`、`rectloom`），没有三维多约束配载、危险品隔离、轴荷与重心、
多站点越站校验、托盘码垛与选箱的组合。moon-stow 从三维几何、约束校验、启发式装箱、
稳定性评估到报表与图纸自成一条链路，见 [SOURCES.md](SOURCES.md) 与 [docs/VALIDATION.md](docs/VALIDATION.md)。

## 许可

Apache-2.0，见 [LICENSE](LICENSE)。