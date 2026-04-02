extends SceneTree

# 快速验证脚本：确认 attribute_names.csv 加载和翻译功能正常。

const ConfigRuntime := preload("res://scripts/systems/config_runtime.gd")
const RoleState := preload("res://scripts/models/role_state.gd")

func _init() -> void:
	var runtime := ConfigRuntime.shared()
	var load_result := runtime.ensure_loaded()
	if not load_result.get("ok", false):
		print("FAIL: config load error: %s" % str(load_result.get("error", "")))
		quit(1)
		return

	# 验证翻译表已加载
	var tests_passed := 0
	var tests_failed := 0

	# 正向映射：internal_key → display_name
	var cases := {
		"physique": "武学",
		"craft": "百艺",
		"insight": "学识",
		"aptitude": "资质",
		"xinxing": "心性",
		"energy": "精力",
		"spirit": "心气",
		"gold": "银两",
	}
	for key in cases.keys():
		var expected: String = cases[key]
		var actual := RoleState.get_display_name(key)
		if actual == expected:
			tests_passed += 1
		else:
			tests_failed += 1
			print("FAIL: get_display_name('%s') = '%s', expected '%s'" % [key, actual, expected])

	# 反向映射：display_name → internal_key
	for key in cases.keys():
		var display: String = cases[key]
		var actual := RoleState.get_internal_key(display)
		if actual == key:
			tests_passed += 1
		else:
			tests_failed += 1
			print("FAIL: get_internal_key('%s') = '%s', expected '%s'" % [display, actual, key])

	# 未知 key 应原样返回
	var unknown := RoleState.get_display_name("unknown_attr")
	if unknown == "unknown_attr":
		tests_passed += 1
	else:
		tests_failed += 1
		print("FAIL: get_display_name('unknown_attr') = '%s', expected 'unknown_attr'" % unknown)

	# 元信息应可读取
	var meta := RoleState.get_attribute_meta("physique")
	if not meta.is_empty() and str(meta.get("display_name", "")) == "武学":
		tests_passed += 1
	else:
		tests_failed += 1
		print("FAIL: get_attribute_meta('physique') unexpected: %s" % str(meta))

	if tests_failed == 0:
		print("OK: all %d tests passed" % tests_passed)
		quit(0)
	else:
		print("DONE: %d passed, %d failed" % [tests_passed, tests_failed])
		quit(1)
