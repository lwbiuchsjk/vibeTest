# 骰池 Assessment 检定方案

## 背景

改造 assessment 检定，从公式系数驱动改为骰池驱动。核心目标：概率由骰子数学自然涌现，不通过手动配置概率系数干预检定过程。

## 一、检定要素

| 要素 | 来源 | 含义 |
|---|---|---|
| 骰池大小 N | `items` 计算出的 score | 掷几颗 d10 |
| 命中阈值 T | `hitThreshold`（事件配置） | 单颗骰 ≥T 算命中 |
| 需要命中数 R | `requiredHits`（事件配置） | 凑够几个命中算通过 |

- 命中阈值 = 任务本身有多苛刻（精度门槛、环境恶劣程度）
- 需要命中数 = 任务需要多全面的能力（复杂度、持续发挥深度）
- 骰池大小 = 角色唯一的对抗手段（属性成长 → 更多骰子）

注意：两个难度维度叠加效果是相乘而非相加，同时拧两个旋钮难度曲线会很陡。

## 二、判定流程

1. 根据 `items` + 角色属性 + `_assessment_thresholds` 计算 score
2. 掷 score 颗 d10，记录每颗骰面
3. 统计命中数 H（骰面 ≥ T 的数量）
4. 判定结果：
   - H ≥ R 且任意骰面 = 10 → **critical_success**
   - H ≥ R 且无 10 → **success**
   - H < R 且任意骰面 = 1 → **critical_fail**
   - H < R 且无 1 → **fail**

critical 设计要点：
- 10 永远是命中（10 ≥ 任何阈值），同时帮助通过检定和触发大成功
- 1 永远不命中（1 < 任何合理阈值），同时拖累失败和触发大失败
- 骰子越多，越容易通过，通过时越容易出现 10；骰子越少，越容易失败，失败时非命中骰越多越容易出现 1

## 三、事件配置格式

变更前：
```
check.type = assessment
check.difficultyStage = 2
check.items = physique:positive;agility:positive
```

变更后：
```
check.type = assessment
check.hitThreshold = 6
check.requiredHits = 2
check.items = physique:positive;agility:positive
```

废弃 `difficultyStage`，新增 `hitThreshold`（int，默认 6）和 `requiredHits`（int，默认 1）。

## 四、代码改动范围

### 4.1 world_event_config_assembler.gd
- 新增解析 `hitThreshold` 和 `requiredHits`
- 移除 `difficultyStage` 解析

### 4.2 rule_engine.gd
- `resolve_check` 的 assessment 分支：替换公式计算为骰池逻辑
- 移除 `_build_assessment_probabilities`
- 新增 `_roll_dice_pool(n, rng)` → 返回骰面数组
- 新增 `_evaluate_dice_pool(dice, hit_threshold, required_hits)` → 返回 result_type
- `_apply_probability_biases` 对 assessment 不再使用（偏置改为加减骰子数）
- `_apply_risk_profile_constraints` 仍在骰池结果之上做门控

### 4.3 world_event_engine.gd
- `_is_check_pass`：偏置参数从百分点转为骰子数增减
- `_print_assessment_debug`：输出改为骰面、命中数、阈值等骰池信息
- `_assessment_thresholds`：保留，仍用于 items → score 的阶段换算

## 五、偏置系统适配

| 偏置字段 | 旧语义 | 新语义 |
|---|---|---|
| `successBias` | 百分点搬运 success↔fail | 加减骰子数（+1 = 多掷 1 颗） |
| `stability_bias` | 叠加到 successBias | 同上，与 successBias 合并 |
| `criticalSuccessBias` | 百分点搬运 cs↔success | 废弃（critical 由骰面 10 自然产生） |
| `criticalFailBias` | 百分点搬运 cf↔fail | 废弃（critical 由骰面 1 自然产生） |

## 六、心性约束层适配

逻辑不变，作用于骰池判定结果之上：

| xinxing | 规则 |
|---|---|
| +2 | 允许 critical_success；额外 +1 骰子 |
| +1 | 允许 critical_success |
| 0 | critical_success → success，critical_fail → fail |
| -1 | 允许 critical_fail |
| -2 | 所有 fail 强制升级为 critical_fail |

+2 阶段的加成从"概率倾斜 5%"改为"+1 骰子"，与新体系一致。

## 七、Chance 检定

不变，仍走 `successRate` 直接指定概率的路径，与骰池 assessment 共存于同一 `resolve_check` 入口。

## 八、数学参考

以命中阈值 ≥6（单颗命中率 50%）为例，不同骰池 vs 需要命中数的通过率：

| 骰池 \ 需要命中 | 1 | 2 | 3 |
|---|---|---|---|
| 2 | 75% | 25% | - |
| 3 | 87.5% | 50% | 12.5% |
| 4 | 93.8% | 68.8% | 31.3% |
| 5 | 96.9% | 81.3% | 50% |
| 6 | 98.4% | 89.1% | 65.6% |
