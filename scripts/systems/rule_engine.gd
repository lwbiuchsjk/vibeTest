extends RefCounted
class_name RuleEngine

# 将属性值裁剪到[min_value, max_value]区间，默认最小值为1。
static func clamp_attribute(value: int, min_value: int = 1, max_value: int = 999999) -> int:
	return clampi(value, min_value, max_value)

# 根据属性当前值和阈值数组，返回阶段值（0 / 1 / 2 / 3）。
# thresholds 为升序阈值数组，例如 [0, 3, 7, 12]。
# value >= thresholds[i] 时进入第 i 阶段，返回最高匹配阶段。
static func get_ability_stage(value: int, thresholds: Array) -> int:
	var stage := 0
	for i in thresholds.size():
		if value >= int(thresholds[i]):
			stage = i
		else:
			break
	return stage

# 从 RoleState 读取指定字段值，调用 get_ability_stage 返回阶段值。
# 说明：路径 A 实现——直接从 RoleState 取值，RoleState 是运行时权威数据源。
static func get_stage_from_role(role_state: Variant, key: String, thresholds: Array) -> int:
	var value := int(role_state.get_value(key, 0))
	return get_ability_stage(value, thresholds)

# 执行鉴定聚合计算：遍历 items，累加正向阶段值、累减负向阶段值，返回综合得分。
# items 格式：[{"key": "physique", "direction": "positive"}, ...]
# role_state：玩家 RoleState，鉴定直接从此处读取数据。
# thresholds：阶段阈值数组，所有项共用同一组阈值。
static func evaluate_assessment(items: Array, role_state: Variant, thresholds: Array) -> int:
	var score := 0
	for item_variant in items:
		var item: Dictionary = item_variant
		var key := str(item.get("key", ""))
		var direction := str(item.get("direction", "positive"))
		var stage := get_stage_from_role(role_state, key, thresholds)
		if direction == "negative":
			score -= stage
		else:
			score += stage
	return score

# 应用资源增减。按设计资源允许为负数。
static func apply_resource_delta(current_value: int, delta: int) -> int:
	return current_value + delta

# 将好感度分值映射为粗粒度档位标签。
static func affinity_tier(score: int) -> String:
	if score < -25:
		return "hatred"
	if score <= 25:
		return "neutral"
	return "favor"

# 统一鉴定判定入口。
# 说明：接收 check 配置、角色状态、风险修正器，返回判定结果。
# Phase 2 占位实现：沿用 score vs difficultyStage 比较，result_type 只返回 success/fail。
# risk_modifiers 完整传入存储但不参与计算。
# thresholds：阶段阈值数组；rng：随机数生成器（chance 类型使用）。
static func resolve_check(
	check: Dictionary,
	role_state: Variant,
	thresholds: Array = [],
	rng: Variant = null,
	risk_modifiers: Dictionary = {}
) -> Dictionary:
	if check.is_empty():
		return {"pass": true, "result_type": "success", "risk_modifiers": risk_modifiers}
	var check_type := str(check.get("type", "")).strip_edges()
	if check_type == "chance":
		# chance 类型：按 successRate 概率判定
		var rate := clampf(float(check.get("successRate", 1.0)), 0.0, 1.0)
		var passed := true
		if rng != null and rng.has_method("randf"):
			passed = rng.randf() <= rate
		else:
			passed = randf() <= rate
		var rt := "success" if passed else "fail"
		return {"pass": passed, "result_type": rt, "risk_modifiers": risk_modifiers}
	if check_type == "assessment":
		# assessment 类型：能力/状态阶段鉴定
		var difficulty_stage := int(check.get("difficultyStage", 0))
		var items: Array = check.get("items", [])
		var score := 0
		if role_state != null and role_state.has_method("get_value"):
			score = evaluate_assessment(items, role_state, thresholds)
		else:
			# JSON 路径回退：从 Dictionary 手动计算
			for item_variant in items:
				var item: Dictionary = item_variant
				var key := str(item.get("key", ""))
				var direction := str(item.get("direction", "positive"))
				var value := 0
				if typeof(role_state) == TYPE_DICTIONARY and role_state != null:
					value = int(role_state.get(key, 0))
				var stage := get_ability_stage(value, thresholds)
				if direction == "negative":
					score -= stage
				else:
					score += stage
		var passed := score >= difficulty_stage
		var rt := "success" if passed else "fail"
		return {"pass": passed, "result_type": rt, "score": score, "risk_modifiers": risk_modifiers}
	# 未知类型默认通过
	return {"pass": true, "result_type": "success", "risk_modifiers": risk_modifiers}

# 执行心性偏移并裁剪至 [-2, +2] 区间。
static func apply_xinxing_delta(current: int, delta: int) -> int:
	return clampi(current + delta, -2, 2)

# 根据心性值返回风险入口配置。
# 说明：决定当前心性阶段下可用的风险机制（孤注一掷 / 主动押注）与稳定收益偏置。
static func get_xinxing_risk_profile(xinxing: int) -> Dictionary:
	match xinxing:
		-2:
			return {"allow_desperate_gamble": false, "allow_preemptive_bet": true, "stability_bias": 0}
		-1:
			return {"allow_desperate_gamble": true, "allow_preemptive_bet": false, "stability_bias": 0}
		0:
			return {"allow_desperate_gamble": true, "allow_preemptive_bet": false, "stability_bias": 0}
		1:
			return {"allow_desperate_gamble": true, "allow_preemptive_bet": false, "stability_bias": 0}
		2:
			# +2 稳定收益预留结构，不实现效果
			return {"allow_desperate_gamble": true, "allow_preemptive_bet": false, "stability_bias": 1}
		_:
			# 超出范围时按 0 处理
			return {"allow_desperate_gamble": true, "allow_preemptive_bet": false, "stability_bias": 0}

# 应用好感度变化，并裁剪到[-100, 100]后返回分值与档位。
static func apply_affinity_delta(current_score: int, delta: int) -> Dictionary:
	var next_score := clampi(current_score + delta, -100, 100)
	return {
		"score": next_score,
		"tier": affinity_tier(next_score)
	}

# 检查移动是否合法。支持LocationGraph对象或原始Dictionary两种输入。
static func can_move(location_graph: Variant, from_location_id: String, to_location_id: String) -> bool:
	if from_location_id == to_location_id:
		return true
	if location_graph == null:
		return false
	if location_graph.has_method("is_neighbor"):
		return location_graph.is_neighbor(from_location_id, to_location_id)
	if typeof(location_graph) == TYPE_DICTIONARY:
		var neighbors: Array = location_graph.get(from_location_id, [])
		return to_location_id in neighbors
	return false

# 统一应用角色变化入口：
# 1) 属性按最小值1与配置的最大值进行裁剪。
# 2) 资源直接执行加减（允许负数）。
static func apply_role_delta(
	role_state: Variant,
	attribute_deltas: Dictionary,
	resource_deltas: Dictionary,
	attribute_max: Dictionary
) -> Dictionary:
	if role_state == null:
		return {"ok": false, "error": "role_state is null"}
	if not role_state.has_method("get_attribute"):
		return {"ok": false, "error": "role_state does not provide get_attribute"}

	for key in attribute_deltas.keys():
		var attr_key := str(key)
		var current := int(role_state.get_attribute(attr_key, 1))
		var delta := int(attribute_deltas[key])
		var max_value := int(attribute_max.get(attr_key, 99))
		var next_value := clamp_attribute(current + delta, 1, max_value)
		role_state.set_attribute(attr_key, next_value)

	for key in resource_deltas.keys():
		var resource_key := str(key)
		var current_resource := int(role_state.get_resource(resource_key, 0))
		var resource_delta := int(resource_deltas[key])
		var next_resource := apply_resource_delta(current_resource, resource_delta)
		role_state.set_resource(resource_key, next_resource)

	return {"ok": true, "role": role_state.to_dict()}
