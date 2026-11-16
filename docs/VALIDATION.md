# 验证说明

本文件说明 moon-stow 的验证方式与可复现步骤。所有断言都在 `moon test` 中，不依赖外部服务。

## 一键复现

```bash
moon version --all      # 记录工具链版本
moon check              # 0 error, 0 warning
moon build              # 构建全部包与示例
moon test               # 32 个测试全部通过
moon fmt                # 格式化后 git diff 应为空
moon run examples/quickstart
```

## 测试覆盖对照

| 规则/能力 | 断言位置 | 验证内容 |
|---|---|---|
| 几何交叠与支撑面积 | `geometry.mbt` | 两个盒子的交叠体积、支撑面积与曼哈顿间距 |
| 六种朝向 | `geometry.mbt` | `Orientation::all()` 与 `keeps_upright()` 的对应关系 |
| 体积/重量/百分比格式化 | `units.mbt` | m³、kg 与 t、百分比、米的字符串输出 |
| 危险品隔离表 | `hazard.mbt` | 表对称性、同级自隔离、分级净距单调 |
| 载具构造 | `load_unit.mbt` | 20ft/40HC/货车/托盘的容积与地板面积 |
| 碰撞与越界 | `pack_scenarios.mbt` | 装不下的超大件进 `unplaced` 并给出原因 |
| 支撑率与层数 | `pack_scenarios.mbt` | 层数上限生效、堆高随之受限 |
| 顶载与易碎 | `pack_scenarios.mbt` | 易碎件上方不得放任何货 |
| 载重上限 | `pack_scenarios.mbt` | 超过 `max_payload_g` 的货物不再放置 |
| 危险品净距 | `pack_scenarios.mbt` | 爆炸品与氧化剂 3 m 净距下只允许放一件 |
| 轴荷与重心 | `stability.mbt`、`verify.mbt` | 杠杆分配、重心偏移带越界告警 |
| 越站顺序 | `pack_scenarios.mbt` | 门口被后送货物占据时报 error |
| 确定性 | `pack_scenarios.mbt` | 同一输入两次装箱得到逐字段相同的布局 |
| 托盘码垛 | `palletize.mbt` | 6 件 400×300×300 在欧标托盘上全部放下且无违规 |
| 选箱 | `cartonize.mbt` | 单件货物选中能装下的最便宜纸箱 |
| 报表 | `report.mbt` | 文本/Markdown/CSV/清单结构正确 |
| SVG | `svg.mbt` | 每个放置一件图元、含俯视/侧视/图例 |
| JSON 作业单 | `scenario.mbt` | 正常解析、缺字段与坏 JSON 报错、序列化稳定 |

## 关键行为验证（人工可复核）

1. **约束与算法同源**：`pack` 在放置前调用与 `verify` 相同的几何/支撑/净距判定，
   因此"自动计划无 error"与"校验器无 error"必须一致。
2. **失败可见**：装不进的货物进入 `plan.unplaced`，附 `no feasible position left in the unit`
   或 `does not fit in a shelf layer`，不会被静默丢弃。
3. **可比较**：`compute_metrics` 对任意放置列表（包括人工调整的）都能重算体积率、重量率、
   重心、堆高与分站重量，便于比较两种策略（见 `examples/pallet`）。
4. **确定性**：所有排序键以 `id` 兜底，两次运行布局逐字段相同（有测试锁定）。

## 已知边界

- 极值点启发式不保证最优；它是给定时间预算下的确定性可行解，指标用于横向比较。
- 危险品净距是欧氏/曼哈顿间距的工程近似，未建模通风、温控与消防分区。
- 托盘码垛按层高对齐，未实现交错咬合（interlock）与缠绕膜约束。
- 轴荷为静力分配，未建模悬挂刚度与动态载荷转移。
