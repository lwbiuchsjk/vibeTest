extends RefCounted

func login_or_create(
	http_request: HTTPRequest,
	base_url: String,
	account: String,
	use_mock_backend: bool
) -> Dictionary:
	if use_mock_backend:
		return _mock_login_or_create(account)

	var payload := {"account": account}
	var body := JSON.stringify(payload)
	var url := "%s/auth/login_or_create" % base_url.rstrip("/")

	var start_err := http_request.request(
		url,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body
	)
	if start_err != OK:
		return {
			"ok": false,
			"error": "Failed to start request (%s)." % start_err
		}

	var completed: Array = await http_request.request_completed
	var request_result: int = completed[0]
	var response_code: int = completed[1]
	var response_body: PackedByteArray = completed[3]

	if request_result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"error": "Network error (%s)." % request_result
		}

	if response_code < 200 or response_code >= 300:
		return {
			"ok": false,
			"error": "HTTP %s: %s" % [response_code, response_body.get_string_from_utf8()]
		}

	var parsed: Variant = JSON.parse_string(response_body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"error": "Invalid JSON response."
		}

	var data := parsed as Dictionary
	var parsed_account := str(data.get("account", "")).strip_edges()
	if parsed_account.is_empty():
		return {
			"ok": false,
			"error": "Response missing account."
		}

	return {
		"ok": true,
		"account": parsed_account,
		"clear_count": int(data.get("clear_count", 0))
	}

func _mock_login_or_create(account: String) -> Dictionary:
	var normalized := account.strip_edges()
	if normalized.is_empty():
		normalized = _generate_account()

	return {
		"ok": true,
		"account": normalized,
		"clear_count": 0
	}

func _generate_account(length: int = 16) -> String:
	const CHARS := "abcdefghijklmnopqrstuvwxyz0123456789"
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var result := ""
	for i in range(length):
		result += CHARS[rng.randi_range(0, CHARS.length() - 1)]
	return result

