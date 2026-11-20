# moon-stow

用 MoonBit 写的确定性三维装载与配载引擎：集装箱配载、托盘码垛、电商选箱、多站点装车，
全部用整数毫米计算，输出可复核的装载计划、逐项规则报告、JSON 装载单和 SVG 示意图。

装载计划不是"能塞进去就行"。真实现场有六类硬约束：不能悬空、不能压坏、不能超重、
不能偏心、危险品须经外部复核、后送的货不能挡前送的货。moon-stow 把这些约束写成可测试的
规则，再由同一个校验器检查自动计划与人工调整后的几何方案。危险品部分仅执行调用方提供的规则和复核记录，不作运输合规判定。

## 快速开始

前提：安装MoonBit工具链。本次复测使用moonc v0.10.21（2026-11-16）；旧派生语法已迁移。
Wasm/WasmGC运行使用moonrun；JavaScript运行还需Node.js。Windows Native需要MSVC及Windows SDK，
本机只有MinGW，因此本轮Native运行受工具链环境阻断，不能计作通过。

从源码使用（克隆后把示例放进自己的模块）：

```bash
git clone https://github.com/niuniu513-ask/moon-stow
cd moon-stow
moon run examples/quickstart
```

本项目尚未确认Mooncakes发布，不能只添加 `moon.pkg` 导入就认为依赖已安装。
当前可复现路径是克隆源码后运行仓库内示例；外部包消费需另行配置本地依赖或在实际发布后安装。
远程仓库可能落后于本地提交；以 [docs/VALIDATION.md](docs/VALIDATION.md) 记录的提交号为准，先切到该提交再复现。

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
| `hazard.mbt` | 危险品声明、具体声明组合规则、整单人工复核快照；未知或禁配时阻断 |
| `load_unit.mbt` | 可替换的20ft/40HC、13.6m厢车、托盘与航空载具矩形演示参数；含空载轴荷 |
| `cargo.mbt` | 货物属性：重量、朝向策略、可堆码层数、顶载上限、易碎、危险品、站点、优先级、间距 |
| `rules.mbt` | 装载规则：最小支撑率、重心偏移带、层数上限、具体声明组合规则与整单复核、越站禁令、轴荷校验 |
| `plan.mbt` | 装载计划数据结构与指标：体积率、重量率、地板占用、重心、堆高、分站重量 |
| `stability.mbt` | 轴荷杠杆分配、地板点载荷、重心偏移、装车后整体归位（货车按轴距中点、集装箱按地板中心） |
| `verify.mbt` | 八组校验：身份、几何朝向、碰撞、支撑/层数/顶载、载重/地板、轴荷/重心、危险品复核门控、越站 |
| `pack.mbt` | 极值点启发式装箱器，带完整约束裁剪、确定性排序、可插拔装载顺序、装箱后自动配平 |
| `palletize.mbt` | 地面按货架排布，再沿能完整承托底面的箱子逐列堆叠 |
| `cartonize.mbt` | 电商选箱：体积重、计费重、按件数与成本择优、空隙率 |
| `report.mbt` | 文本报告、Markdown 报告、CSV 装载单、分站送货清单 |
| `svg.mbt` | 俯视图 / 侧视图 / 合并 SVG 图纸，按站点着色 |
| `scenario.mbt` | JSON 作业单解析、装载计划 JSON 序列化（稳定字段顺序，便于 CI 比对） |

## 三个使用场景

### 1. 集装箱几何规划与危险品人工复核

`moon run examples/hazard` 展示盐酸（UN1789，第 8 类）与次氯酸钠溶液
（UN1791，第 8 类，有效氯 12%）的整单阻断：ICSC 1119 提示遇酸产生氯气，
调用方据此提供企业禁同柜规则。相同类别不代表相容，增加箱内净距不能解除禁配。
这条企业策略不冒充 IMDG 条文；浓度、包装类别与 SDS 引用均为虚构测试输入。

默认不带危险品关系数据库。缺少具体组合规则、声明引用或整单人工复核记录时，
`pack` / `pack_all` / `palletize` 阻断该货单，`verify` 对未装入的货物也保留诊断。
`cartonize` 对含危险品的整单返回未分箱，防止自动选箱变成未经复核的拆单依据。

外部复核记录与载具、完整货单和组合规则快照绑定；改数量、声明版本、载具或规则后须重审。
复核通过仅允许几何计算，输出仍注明 `dangerous-goods-geometry-only`，不代表可同柜或可承运。
详见 [危险品边界与案例](docs/HAZARD-REVIEW.md)。原类别矩阵与距离映射已移除。

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
moon run examples/hazard       # 具体物质禁配、未知关系、人工复核后的几何规划
moon run examples/verify       # 手工改坏一份装载图，看校验器逐条抓出来
```

## 校验

```bash
moon check --deny-warn
moon test
moon fmt --check
```

`moon test` 覆盖：几何交叠与支撑面积、六朝向、具体声明禁配、未知关系、失效复核快照、危险品输入错误、边界与碰撞、支撑率与层数、
顶载与易碎、载重与地板点载荷、轴荷分配、重心带、越站顺序、确定性（两次运行同布局）、
JSON 解析与序列化、报告与 SVG 结构。

## 设计取舍

- **整数毫米**：所有坐标、体积、重量都用整数，避开浮点误差导致的"差 1 mm 判碰撞"问题；
  体积用 `Int64` mm³，格式化时才转成 m³。
- **校验器与装箱器共用同一套几何与规则**：自动计划与人工调整的计划用完全相同的判定，
  危险品整单门控同时用于自动规划与独立校验；通过仅表示当前输入下未检出相应错误。
- **确定性优先**：排序键带 id 兜底，同样输入永远得到同样布局，便于 CI 比对与现场复现。
- **失败要说明原因**：装不进去的货进 `unplaced` 并附原因，不静默丢弃。
- **装完自动配平**：极值点启发式总是从门口角落往里长，重心天然偏前；装箱结束后整批货一起平移，
  让重心落到平衡点上——货车按轴距中点（重量压在轮子之间），集装箱与托盘按地板中心——
  平移被限制在自由空间内，所以贴墙的货只会往回移，不会穿墙。平移不改变相对几何，
  支撑、堆码、声明间距和越站的相对关系不变，最终仍需检查轴荷及其他诊断。

## 与已有工作的区别

2026-11-16 的有限检索记录中，相邻 MoonBit 装箱模块是**二维**矩形布局/纹理图集
（如 `moon_binpack`、`rectloom`），没有三维多约束配载、危险品复核门控、轴荷与重心、
多站点越站校验、托盘码垛与选箱的组合。moon-stow 从三维几何、约束校验、启发式装箱、
稳定性评估到报表与图纸自成一条链路，见 [SOURCES.md](SOURCES.md) 与 [docs/VALIDATION.md](docs/VALIDATION.md)。

## 许可

Apache-2.0，见 [LICENSE](LICENSE)。
## 规划结果的适用范围

必须检查 `unplaced`、`violations` 和 `planning_scope`；缺货按Error报告，不能把部分规划当完整成功。
自动启发式可能输出带最终轴荷诊断的方案，`pack_all`仅在整单完整且无Error时返回结果。
顶载与地板压力包含全部可达上层货物；多底座桥接时，对各底座保守计入全部重量，未求解真实反力分配。
轴荷包含显式提供的空载轴荷；轴距外货物归最近轴，未建模悬挑反力、车辆动态或实际法规限值。
默认载具尺寸/载荷仅供演示，实际箱内尺寸、设备铭牌、车辆轴位和空载称重必须由调用方替换。
航空载具仅为矩形示例，未实现LD3轮廓。`with_gap`只约束同一高度带上并列货物的侧向净距，堆叠不受影响，也不代表通风或法规隔离。
输入数值范围、精确单位及其他限制见 [API.md](docs/API.md)；启发式不保证最优，代码测试不替代现场验证。
