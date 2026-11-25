# 验证说明

本文件说明 moon-stow 的验证方式与可复现步骤。所有断言都在 `moon test` 中，不依赖外部服务。

## 一键复现

```bash
moon version --all      # 记录工具链版本
moon check              # 0 error, 0 warning
moon build              # 构建全部包与示例
moon test               # 以当前命令实际统计为准
moon fmt --check        # 格式化检查
moon run examples/quickstart
```

## 测试覆盖对照

| 规则/能力 | 断言位置 | 验证内容 |
|---|---|---|
| 几何交叠与支撑面积 | `geometry.mbt` | 两个盒子的交叠体积、支撑面积、三轴曼哈顿间距，以及侧向净距与高度带判定 |
| 六种朝向 | `geometry.mbt` | `Orientation::all()` 与 `keeps_upright()` 的对应关系 |
| 体积/重量/百分比格式化 | `units.mbt` | m³、kg 与 t、百分比、米的字符串输出 |
| 危险品整单门控 | `hazard_scenarios.mbt` | 同类具体物质禁配、未知关系、单件复核、快照变化、冲突规则、非法声明与输出边界 |
| 载具构造 | `load_unit.mbt` | 20ft/40HC/货车/托盘的容积与地板面积 |
| 碰撞与越界 | `pack_scenarios.mbt` | 装不下的超大件进 `unplaced` 并给出原因 |
| 支撑率与层数 | `pack_scenarios.mbt` | 层数上限生效、堆高随之受限 |
| 顶载与易碎 | `pack_scenarios.mbt` | 易碎件上方不得放任何货 |
| 载重上限 | `pack_scenarios.mbt` | 超过 `max_payload_g` 的货物不再放置 |
| 危险品默认阻断 | `pack_scenarios.mbt` | 未经复核时整单不规划，不自动形成拆单结论 |
| 轴荷与重心 | `stability.mbt`、`verify.mbt` | 杠杆分配、重心偏移带越界告警 |
| 装载配平 | `stability.mbt` | 角落单件被滑到地板中心、重心偏移归零；整车按轴距中点配平；贴墙满宽货件不再移动 |
| 越站顺序 | `pack_scenarios.mbt` | 门口被后送货物占据时报 error |
| 确定性 | `pack_scenarios.mbt` | 同一输入两次装箱得到逐字段相同的布局 |
| 托盘码垛 | `palletize.mbt` | 6 件 400×300×300 在欧标托盘上全部放下且无违规 |
| 选箱 | `cartonize.mbt` | 单件货物选中能装下的最便宜纸箱 |
| 报表 | `report.mbt` | 文本/Markdown/CSV/清单结构正确 |
| SVG | `svg.mbt` | 每个放置一件图元、含俯视/侧视/图例 |
| JSON 作业单 | `scenario.mbt` | 正常解析、缺字段与坏 JSON 报错、序列化稳定 |

## 关键行为验证（人工可复核）

1. **约束与算法同源**：`pack` 在放置前调用与 `verify` 相同的几何/支撑判定及整单危险品门控，
   自动方案最终仍经verify检查；轴荷等整车条件可能报错，不能承诺所有自动输出可用。
2. **失败可见**：装不进的货物进入 `plan.unplaced`，附 `no feasible position left in the unit`
   或 `does not fit in a shelf layer`，不会被静默丢弃。
3. **装完自动配平**：`pack` 与 `palletize` 在产出计划前对整批货做一次平移，把重心挪到平衡点
   （有轴的车按轴距中点，其余按地板中心），平移量被自由空间夹住；平移不改变相对几何，
   所以支撑、堆码、隔离与越站的判定与平移前一致（有测试锁定）。
4. **可比较**：`compute_metrics` 对任意放置列表（包括人工调整的）都能重算体积率、重量率、
   重心、堆高与分站重量，便于比较两种策略（见 `examples/pallet`）。
5. **确定性**：所有排序键以 `id` 兜底，两次运行布局逐字段相同（有测试锁定）。

## 已知边界

- 极值点启发式不保证最优；结果确定但可能装不全或出现整车约束诊断，须结合未装入列表与verify结果判断。
- 危险品不作 IMDG 法规判定；没有完整 DGL/特殊隔离条款、相容性数据库或真实外部复核。通风、温控、消防分区、包装及运输条件须外部评审；复核记录只允许几何规划。
- 托盘码垛为地面货架排布加逐列堆叠，未实现交错咬合（interlock）与缠绕膜约束。
- 轴荷为静力分配，未建模悬挂刚度与动态载荷转移。
## 危险品专项复现

运行 `moon run examples/hazard`，依次观察：同为第 8 类的盐酸/次氯酸钠被企业规则禁止同柜；
无具体组合规则时整单暂停；单件也因缺复核而暂停；虚构的外部复核完成后仅输出带警示的几何计划。
测试还独立构造相距 9.4 m 的手工布局，断言禁配仍然报错；禁止通过调整位置解除禁配。
`hazard_scenarios.mbt` 是可执行证据，不能证明真实危险品运输合规。具体证据链见 [HAZARD-REVIEW.md](HAZARD-REVIEW.md)。

## 2026-11-18再次自查的新增回归

`audit_scenarios.mbt`复现并锁定：三层累计顶载/地板压力、正常吨位轴荷力矩、选箱原始货物索引、
超大件旁的小件仍可选箱、声明间距、反向车门/篡改站点、大面积支撑率，以及无效手工布局、
空载轴荷、数值上限、缺货与严格JSON输入。新工具链已迁移为`#derive`语法。
Windows Native当前因运行时要求MSVC且本机为MinGW阻断；Wasm/WasmGC/JS结果见私人自查报告。

## 2026-11-20 声明净距语义修正与本轮验证

本轮把 `with_gap` 从"任意一对货物的曼哈顿盒距"改为"同一高度带内并列货物的侧向净距"。
原实现下，设置声明净距的货物无法互相堆叠（堆叠时盒距必然为 0），装箱器还把堆叠候选点抬到
`max_z + gap`，产生悬空候选。现在 `geometry.mbt` 提供 `Aabb::side_gap`（只算 x+y）与
`Aabb::shares_height`，`verify` 与 `pack` 用同一判定：共享高度带才比较侧向净距，堆叠不受限。

| 项目 | 本轮结果 |
|---|---|
| 代码提交 | `818d948`（危险品门控重写 + 净距语义 + 回归） |
| 文档提交 | `1a9355b`；本记录随之提交 |
| `moon check --deny-warn` | 0 error / 0 warning |
| `moon test` | wasm / wasm-gc / js 三个目标各 72 passed / 0 failed（净距语义与堆叠新增回归） |
| `moon check --deny-warn --target all` | 通过（42 tasks） |
| `moon fmt --check` | no work to do |
| 六个示例 | quickstart / pallet / cartonize / multistop / hazard / verify 全部 exit 0 |
| README 代码块 | 用同一段代码重跑，输出与 README 逐字节一致（3 of 3 件、1.792 m³、64.000 kg） |
| 工具链 | `moonc v0.10.21+06da1ed44`（2026-11-16）；Native 仍需 MSVC，本机 MinGW 未能执行，不计作通过 |

复现命令：

```bash
git checkout 1a9355b
moon check --deny-warn
moon test
moon fmt --check
for e in quickstart pallet cartonize multistop hazard verify; do moon run examples/$e; done
```

## 2026-11-25 装载质量模式与本轮验证

本轮把"装得更多"从一句口号变成可复现的数字：新增 `pack_best`（六种排序 × 两轮重试，按件数、
体积率、堆高取最优），并把 `floor_used_area` 改成真正的并集，`better()` 的朝向兜底改成
文档一直声称的"声明顺序优先"。实测口径、完整表格与复现脚本在 [QUALITY.md](QUALITY.md)。

| 项目 | 本轮结果 |
|---|---|
| `moon check --deny-warn` | 0 error / 0 warning |
| `moon check --deny-warn --target all` | 通过 |
| `moon test` | 76 passed / 0 failed（新增 `pack_best`、排序、地板并集回归） |
| `moon fmt --check` | no work to do |
| `moon info` 后 `pkg.generated.mbti` | 已重新生成，无残留差异 |
| 六个示例 | quickstart / pallet / cartonize / multistop / hazard / verify 全部 exit 0 |
| README 代码块 | 用同一段代码重跑，输出与 README 逐字节一致（`centre y 1.17 m`，三件 LWH） |
| 质量对比 | 20ft 80 件：57 → 73 件（26.2% → 55.5%）；欧标托盘 160 件：6 → 27 件 |
| 工具链 | `moonc v0.10.21+06da1ed44`；Native 仍需 MSVC，本机 MinGW 未能执行，不计作通过 |

复现命令：

```bash
moon check --deny-warn --target all
moon test
moon fmt --check
moon run examples/quickstart
```
