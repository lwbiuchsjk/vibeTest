# 阶段 2 配置归档

## 归档时间
2026-05-08

## 归档原因
当前版本完整主路径 MVP 设计文档（[[当前版本完整主路径_MVP设计]]）落地阶段，按 Phase A（占位骨架数据填入）思路，决定**直接创建符合新设计意图的测试数据**而非迁移改造旧数据。

## 归档内容
本目录是阶段 2 38 事件 + 6 角色精调成果的完整 CSV 配置快照（不含 `.csv.import` 文件，避免与新配置 uid 冲突；目录加 `.gdignore` 让 Godot 跳过资源导入）。

## 用途
- 真实文本撰写期（Phase B）参考：6 角色精调后的填充事件叙事文本可作为新事件的语料来源
- 角色对话/选项/outcome 的语义参考
- 任务定义参考（met_he 新增 / met_lu 删除时对照旧 met_lu 任务结构）

## 不再使用的内容
- 旧 4 地点：loc_pharmacy / loc_market / loc_training_ground / loc_outskirts
  - 新设计：loc_pharmacy（保留）/ 家+市场合并地点（替代 loc_market）/ loc_training_ground（保留）/ loc_dao_temple（替代 loc_outskirts，承担道观语义）
- 旧 4 骨架：met_cheng / met_lu / met_zhou / life_cost
  - 新设计：新增 met_he（药铺·何守仁首遇）；保留 met_cheng（道观·程叔衡）/ met_zhou（练场·周既明）；life_cost 归属由新数据决议（改名 met_qin 或保留并新增 met_qin）；删除 met_lu（陆首遇延后到拜师 chain 屏 3/4 承担）
- 自省事件：仅 sys_reflection 占位
  - 新设计：三独立 event_id（sys_opening_reflection / sys_reflection / sys_final_reflection）

## 设计基线
[[当前版本完整主路径_MVP设计]]
[[当前版本完整主路径_落地进度]]
