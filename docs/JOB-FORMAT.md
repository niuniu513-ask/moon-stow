# 作业单格式（JSON）

`parse_scenario` 吃一个 JSON 文档，返回 `LoadUnit` + `Array[Cargo]` + `StowRules`。
字段名就是订单系统里能直接落库的名字，下面这份是完整示例，所有字段都可以验证：

```json
{
  "unit": { "type": "container_40hc", "id": "MSKU7654321" },
  "items": [
    {
      "id": "PLT-A01",
      "size": [1200, 800, 1450],
      "weight_kg": 420,
      "upright": "keep_upright",
      "stop": 1,
      "priority": 5,
      "gap_mm": 50,
      "group": "pallet",
      "stackable": false
    },
    {
      "id": "CTN-B07",
      "size": [600, 400, 350],
      "weight_kg": 18,
      "upright": "free",
      "stop": 2,
      "max_layers": 4,
      "top_load_kg": 60,
      "fragile": false,
      "hazard": { "class": "3", "un": "UN1263", "group": "II" }
    }
  ],
  "rules": {
    "min_support_permille": 700,
    "cog_margin_permille": 600,
    "max_stack_layers": 4,
    "overstow": true,
    "axles": true
  }
}
```

## unit

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `type` | 是 | `container_20ft`、`container_40hc`、`truck_rigid`、`pallet_eur`、`pallet_iso`、`air_uld` |
| `id` | 否 | 箱号/车牌/托盘号，缺省时用 `type` 当 id |

未知的 `type` 直接返回错误，不会退化成默认箱型：一个拼错的箱型比一个装满的错箱子便宜。

## items[]

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| `id` | 必填 | 货物唯一标识，非空且唯一，重复时拒绝解析 |
| `size` | 必填 | `[长, 宽, 高]`，毫米，必须正好三个1到30000的整数 |
| `weight_kg` | 0 | 千克，0到2000000；换算成克（×1000），负数/错误类型拒绝 |
| `upright` | `keep_upright` | `keep_upright`、`free`/`any`、`fixed`/`this_side_up` |
| `stop` | 0 | 送货站点序号，0 表示第一站 |
| `priority` | 0 | 同站点内的装车优先级，大的先装（更靠里） |
| `gap_mm` | 0 | 与同一高度带上并列货物的最小侧向净距（x+y，毫米），取两件声明值较大者；堆叠不受此值限制 |
| `group` | 空 | 分组标签，报告与清单按它聚合 |
| `fragile` | false | `true` 等于"顶上不许压任何东西" |
| `stackable` | true | `false` 等于最大堆叠层数 1、顶载 0 |
| `max_layers` | 不限制 | 自身最多被堆几层；给了它就可以配 `top_load_kg` |
| `top_load_kg` | 60（当有 `max_layers` 时） | 顶面允许承受的最大重量，千克 |
| `hazard` | 无 | `{ "class": "3", "un": "UN1263", "group": "II" }`，`group` 可省略或取 `I`/`II`/`III`/`N/A`，可选 `declaration_ref` 指向确切 SDS/声明版本 |

`size` 里出现负数或长度不足三会返回 `items[i]: incomplete item`，错误里带下标，
不用去猜是哪一行。

## rules

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| `min_support_permille` | 700 | 底面积至少被支撑的千分比 |
| `cog_margin_permille` | 600 | 重心允许偏离地板中心的千分比 |
| `max_stack_layers` | 不限 | 全局堆叠层数上限 |
| `overstow` | true | 是否检查"后装先卸"（`false` 关闭该组校验） |
| `axles` | true | 是否检查轴荷（`false` 关闭该组校验） |

## 错误信息

`parse_scenario` 的错误都是可以直接贴进日志的中文/英文短句，例如：

```
invalid JSON document
missing "unit"
unit: unknown or incomplete unit description
missing "items"
items: must be an array
items[2]: incomplete item
```

解析成功之后的装载问题（装不下、超重、重心偏）不属于解析错误，它们出现在
`LoadPlan::unplaced` 与 `LoadPlan::violations` 里，这样一份"部分成功"的作业单也能
照样出报告。

## 危险品输入与复核边界

提供 `hazard` 时，必须有已识别的字符串类别与合法四位 UN 编号（支持 `1789` 或 `UN1789`，不接受 `0000`）。
非法对象、类别、编号、包装类别或声明引用类型直接报 `items[i]: incomplete item`，不会降级为普通货。
该检查仅验证格式，不查验 UN 编号是否对应真实物质及所报类别。

本 JSON 格式不接收危险品组合规则和人工复核记录；危险品作业解析成功后，规划仍默认阻断。
须由上层应用补入 `HazardPairRule` 与 `HazardReview`，详见 [HAZARD-REVIEW.md](HAZARD-REVIEW.md)。
遗漏 `hazard` 字段仍表示调用方声明为普通货，本库不从货物名称猜测危险性。
JSON 输出新增 `planning_scope`；CSV 每行也有同名列，送货清单与 SVG 标明输出适用范围。

数值和枚举错误不静默转换：尺寸必须正好三个整数，未知upright、负重量、非法布尔值、
负站点、无效间距与规则范围均拒绝。规则support/cog取0..1000；规划接口还执行累计质量和体积范围检查。
`parse_rules`、`upright_of`等低层辅助函数仍保留历史默认行为；外部作业应使用 `parse_scenario` 完整解析。
