# 装载质量实测

本文件记录 `pack`（默认启发式）与 `pack_best`（质量模式）在同一批货单上的实测差异，
以及复现方法。数字来自本机真实运行输出，不是估算。

## 口径

- **主口径是"装入件数"**：货代问的第一件事是"我这批货能进多少"，件数直接回答它。
- 件数相同时取体积利用率高的方案，再相同取堆高低的方案。
- 体积利用率单独列出，因为两种口径会指向不同方案（见文末"为什么不用体积优先"）。

## 方法

货单是确定性伪随机生成的，不依赖外部数据：10 种箱规（300×300×300 到 1200×800×600）、
密度 120 g/L、允许 4 层且顶载 400 kg，每 13 件取一件易碎（不可承压），
每 17 件取一件声明净距 50 mm，投递站点在 1–3 之间轮转。种子固定，所以每次生成完全一致。

## 结果

载具：20ft（5898×2352×2393）、40HC（12032×2352×2698）、欧标托盘（1200×800×1800）。

| 载具 | 件数 | pack 装入 | pack 体积率 | pack_best 装入 | pack_best 体积率 |
|---|---|---|---|---|---|
| 20ft | 20 | 18 | 6.8% | **19** | **10.6%** |
| 20ft | 40 | 31 | 12.1% | **37** | **26.6%** |
| 20ft | 80 | 57 | 26.2% | **73** | **55.5%** |
| 20ft | 160 | 101 | 46.6% | **102** | **47.3%** |
| 40HC | 20 | 18 | 3.0% | **19** | **4.6%** |
| 40HC | 40 | 31 | 5.3% | **37** | **11.6%** |
| 40HC | 80 | 58 | 11.7% | **75** | **24.8%** |
| 40HC | 160 | 120 | 28.2% | **123** | **29.4%** |
| 欧标托盘 | 20 | 6 | 18.0% | **10** | **28.2%** |
| 欧标托盘 | 40 | 6 | 18.0% | **14** | **29.5%** |
| 欧标托盘 | 80 | 6 | 18.0% | **19** | **35.3%** |
| 欧标托盘 | 160 | 6 | 18.0% | **27** | **47.4%** |

读法：

- 20ft 装 80 件时，默认口径只能放进 57 件、占 26.2% 体积；质量模式放进 73 件、占 55.5%。
- 托盘上的差距最大，因为托盘地板小、能放的位置少，排序错了就整层浪费：6 件 → 27 件（160 件货单）。
- 160 件的大货单已经贴住载具上限（20ft 堆高 2350 mm / 2393 mm），改进空间自然变小。

## 代价

质量模式对每个排序各跑一遍、每遍带两轮重试，实测 24 次完整运行合计 3.5 s（js 目标，本机）。
默认 `pack` 只跑一遍，不重试。两者都是确定性的：同一输入两次运行逐字段相同（有测试锁定）。

## 复现

在仓库根目录建一个临时示例目录，写入下面两个文件，然后跑它：

```moonbit
// examples/_quality/moon.pkg
import {
  "niuniu513-ask/moon-stow",
}

pkgtype(kind: "executable")
```

```moonbit
// examples/_quality/main.mbt
fn lcg(state : Int32) -> Int32 {
  (state * 1103515245 + 12345) & 0x7fffffff
}

fn stress_set(
  count : Int32,
  seed : Int32,
  density : Int32,
  top_load : Int32,
) -> Array[@moon-stow.Cargo] {
  let dims_list : Array[(Int32, Int32, Int32)] = [
    (600, 400, 400), (400, 300, 300), (800, 600, 500), (1200, 800, 600),
    (1000, 1000, 700), (500, 400, 350), (700, 500, 450), (300, 300, 300),
    (1150, 750, 550), (900, 650, 480),
  ]
  let out : Array[@moon-stow.Cargo] = []
  let mut s = seed
  for i in 0..<count {
    s = lcg(s)
    let (l, w, h) = dims_list[(s % 10).to_int()]
    s = lcg(s)
    let stop = 1 + (s % 3).to_int()
    s = lcg(s)
    let priority = (s % 6).to_int()
    let litres = l * w * h / 1_000_000
    let mut cargo = @moon-stow.Cargo::new(
      "C" + i.to_string(),
      @moon-stow.Dimensions::new(l, w, h),
      litres * density,
    ).with_stop(stop).with_priority(priority).with_stack_limit(4, top_load)
    if i % 13 == 0 {
      cargo = cargo.fragile_item()
    }
    if i % 17 == 0 {
      cargo = cargo.with_gap(50)
    }
    out.push(cargo)
  }
  out
}

fn line(tag : String, plan : @moon-stow.LoadPlan) -> String {
  let m = plan.metrics
  tag + " " + m.placed_count.to_string() + "/" + m.cargo_count.to_string() +
  " vol " + (m.volume_utilization_permille.to_double() / 10.0).to_string() +
  " floor " + (m.floor_utilization_permille.to_double() / 10.0).to_string() +
  " h " + m.stack_height_mm.to_string()
}

fn main {
  let units : Array[(String, @moon-stow.LoadUnit)] = [
    ("20ft", @moon-stow.LoadUnit::container_20ft("C20")),
    ("40hc", @moon-stow.LoadUnit::container_40hc("C40")),
    ("eur", @moon-stow.LoadUnit::pallet_eur("P1")),
  ]
  for u in units {
    let (name, unit) = u
    for n in [20, 40, 80, 160] {
      let cargos = stress_set(n, 7, 120, 400_000)
      let rules = @moon-stow.StowRules::default()
      println(name + " n=" + n.to_string() + " | " + line("pack", @moon-stow.pack(unit, cargos, rules)))
      println(name + " n=" + n.to_string() + " | " + line("best", @moon-stow.pack_best(unit, cargos, rules)))
    }
  }
}
```

```bash
moon run --target js examples/_quality
```

跑完把 `examples/_quality` 删掉即可，本仓库不保留这个临时包。

## 边界

- 这是同一货单上的方法对比，不是行业基准，也没有与商业装箱器对拍。
- 件数优先不代表运费最优：危险品、卸货顺序、单件超重都会推翻"多装几件"的结论，
  整车约束的诊断仍在 `plan.violations` 里，须逐条看。
- 托盘结果看起来差（20 件货单只进 6 件），主因是这批货的 3 个站点在 1.2 m 长的托盘上
  互相卡住退让位置，不是代码缺陷；换成同站点货单明显好转。
- **为什么不用体积优先**：试过按体积取最优，欧标托盘上它会选出"只装 3 件、占 94% 体积"
  的方案——一件大箱子吃满托盘，剩下 37 件全部 `unplaced`。那个方案在数学上漂亮，
  在业务上是废物，所以口径改成件数优先。
