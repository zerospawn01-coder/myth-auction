extends RefCounted
class_name AgentNegotiationGate

const DEFAULT_RULES := {
	"weights": {
		"base_priority": 1.0,
		"severity": 2.0,
		"confidence": 1.0,
		"collapse_urgency": 2.5,
		"scenario_progress": 0.75,
		"ledger_conflict": 2.0,
		"cost_penalty": 1.0,
		"cooldown_penalty": 20.0,
		"cast_manager_direct_write_penalty": 1000.0
	},
	"tie_threshold": 0.5,
	"collapse_timer_window": 100.0,
	"narrative_templates": {
		"approved": "Intercepted audit line: gate ruling accepted.",
		"escalated": "Intercepted audit line: data interference detected; auditor ruling required.",
		"cast_trigger": "Intercepted audit line: CastManager flag accepted; priority injection queued.",
		"rejected": "Intercepted audit line: proposal rejected by governance constraints.",
		"none": "Intercepted audit line: no actionable proposal."
	},
	"cast_manager_triggers": {
		"flag_contradiction": [
			{"agent_id": "Director", "prompt_variable": "priority_coverup", "delta": 20, "ttl_turns": 1},
			{"agent_id": "Engineer", "prompt_variable": "priority_repair", "delta": 25, "ttl_turns": 1}
		],
		"request_repair": [
			{"agent_id": "Engineer", "prompt_variable": "priority_repair", "delta": 30, "ttl_turns": 1}
		],
		"request_coverup": [
			{"agent_id": "Director", "prompt_variable": "priority_coverup", "delta": 30, "ttl_turns": 1}
		]
	}
}

var rules: Dictionary = DEFAULT_RULES.duplicate(true)


func load_rules(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return false
	if typeof(parser.data) != TYPE_DICTIONARY:
		return false

	var parsed_rules: Dictionary = parser.data
	rules = _merge_dictionaries(DEFAULT_RULES.duplicate(true), parsed_rules)
	return true


func evaluate_proposals(proposals: Array, ledger: Dictionary = {}) -> Dictionary:
	if proposals.is_empty():
		return _build_result("none", {}, {}, [], "no_proposals")

	var scored_proposals = []
	var score_map = {}
	var valid_count = 0

	for index in range(proposals.size()):
		var proposal_value = proposals[index]
		if typeof(proposal_value) != TYPE_DICTIONARY:
			continue

		var proposal = _as_dictionary(proposal_value)
		var proposal_id = _proposal_id(proposal, index)
		var violations = _proposal_violations(proposal)
		var score = _score_proposal(proposal, ledger)
		if violations.is_empty():
			valid_count += 1

		score_map[proposal_id] = score
		scored_proposals.append({
			"id": proposal_id,
			"proposal": proposal,
			"score": score,
			"violations": violations
		})

	if scored_proposals.is_empty():
		return _build_result("none", {}, score_map, [], "no_valid_proposal_shape")
	if valid_count == 0:
		return _build_result("rejected", {}, score_map, [], "governance_constraints")

	scored_proposals.sort_custom(Callable(self, "_sort_by_score_descending"))
	var top = _as_dictionary(scored_proposals[0])
	var top_violations = _as_array(top.get("violations", []))
	var top_proposal = _as_dictionary(top.get("proposal", {}))
	if not top_violations.is_empty():
		return _build_result("rejected", top_proposal, score_map, [], _join_strings(top_violations, "+"))

	var tied_candidates = _find_tied_candidates(scored_proposals)
	if tied_candidates.size() > 1:
		var result = _build_result("escalated", top_proposal, score_map, [], "score_tie")
		result["candidates"] = tied_candidates
		return result

	var winner = top_proposal
	var trigger_injections = _build_trigger_injections(winner)
	var status = "approved"
	var reason = "highest_weight"
	if _is_cast_manager_proposal(winner) and not trigger_injections.is_empty():
		reason = "cast_manager_trigger"

	return _build_result(status, winner, score_map, trigger_injections, reason)


func _score_proposal(proposal: Dictionary, ledger: Dictionary) -> float:
	var weights = _rule_dictionary("weights")
	var severity = float(proposal.get("severity", 0.0))
	var base_priority = float(proposal.get("base_priority", 0.0))
	var timer_sensitivity = float(proposal.get("timer_sensitivity", clamp(severity / 100.0, 0.0, 1.0)))
	var scenario_relevance = float(proposal.get("scenario_relevance", clamp(base_priority / 100.0, 0.0, 1.0)))
	var score = 0.0
	score += base_priority * float(weights.get("base_priority", 1.0))
	score += severity * float(weights.get("severity", 1.0))
	score += float(proposal.get("confidence", 1.0)) * float(weights.get("confidence", 1.0))
	score += _collapse_urgency_score(ledger) * timer_sensitivity * float(weights.get("collapse_urgency", 1.0))
	score += _scenario_progress_score(ledger) * scenario_relevance * float(weights.get("scenario_progress", 1.0))
	score += _ledger_conflict_score(proposal, ledger) * float(weights.get("ledger_conflict", 1.0))
	score -= float(proposal.get("cost", 0.0)) * float(weights.get("cost_penalty", 1.0))

	if _is_on_cooldown(proposal, ledger):
		score -= float(weights.get("cooldown_penalty", 20.0))
	if _is_cast_manager_proposal(proposal) and bool(proposal.get("direct_card_write", false)):
		score -= float(weights.get("cast_manager_direct_write_penalty", 1000.0))

	return score


func _collapse_urgency_score(ledger: Dictionary) -> float:
	if not ledger.has("collapse_timer_remaining"):
		return 0.0

	var window = max(1.0, float(rules.get("collapse_timer_window", 100.0)))
	var remaining = clamp(float(ledger.get("collapse_timer_remaining", window)), 0.0, window)
	return ((window - remaining) / window) * 100.0


func _scenario_progress_score(ledger: Dictionary) -> float:
	if not ledger.has("scenario_progress"):
		return 0.0

	var progress = float(ledger.get("scenario_progress", 0.0))
	if progress <= 1.0:
		progress *= 100.0
	return clamp(progress, 0.0, 100.0)


func _ledger_conflict_score(proposal: Dictionary, ledger: Dictionary) -> float:
	var conflict_count = 0
	var conflict_flags = ledger.get("conflict_flags", [])
	if typeof(conflict_flags) == TYPE_ARRAY:
		conflict_count += conflict_flags.size()

	var target = str(proposal.get("target", ""))
	var target_conflicts = ledger.get("target_conflicts", {})
	if not target.is_empty() and typeof(target_conflicts) == TYPE_DICTIONARY:
		conflict_count += int(target_conflicts.get(target, 0))

	return float(conflict_count)


func _proposal_violations(proposal: Dictionary) -> Array[String]:
	var violations: Array[String] = []
	if _is_cast_manager_proposal(proposal) and bool(proposal.get("direct_card_write", false)):
		violations.append("cast_manager_direct_card_write")
	return violations


func _build_trigger_injections(proposal: Dictionary) -> Array:
	if not _is_cast_manager_proposal(proposal):
		return []

	var triggers = _rule_dictionary("cast_manager_triggers")
	var action_type = str(proposal.get("action_type", ""))
	var injection_templates = triggers.get(action_type, [])
	if typeof(injection_templates) != TYPE_ARRAY:
		return []

	var injections = []
	for injection_value in injection_templates:
		if typeof(injection_value) != TYPE_DICTIONARY:
			continue
		var injection = _as_dictionary(injection_value).duplicate(true)
		injection["source_agent_id"] = str(proposal.get("agent_id", "CastManager"))
		injection["source_proposal_id"] = str(proposal.get("id", ""))
		injection["target"] = str(proposal.get("target", ""))
		injections.append(injection)
	return injections


func _build_result(status: String, winner: Dictionary, scores: Dictionary, trigger_injections: Array, reason: String) -> Dictionary:
	return {
		"status": status,
		"winner": winner,
		"scores": scores,
		"trigger_injections": trigger_injections,
		"reason": reason,
		"narrative_log": _narrative_for_status(status, reason, trigger_injections)
	}


func _narrative_for_status(status: String, reason: String, trigger_injections: Array) -> String:
	var templates = _rule_dictionary("narrative_templates")
	var default_templates = _as_dictionary(DEFAULT_RULES.get("narrative_templates", {}))
	if status == "approved" and not trigger_injections.is_empty():
		return str(templates.get("cast_trigger", default_templates.get("cast_trigger", "")))
	if status == "rejected":
		return "%s reason=%s" % [templates.get("rejected", default_templates.get("rejected", "")), reason]
	return str(templates.get(status, default_templates.get(status, "")))


func _find_tied_candidates(scored_proposals: Array) -> Array:
	if scored_proposals.is_empty():
		return []

	var tie_threshold = float(rules.get("tie_threshold", 0.5))
	var top_item = _as_dictionary(scored_proposals[0])
	var top_score = float(top_item.get("score", 0.0))
	var tied = []
	for item_value in scored_proposals:
		var item = _as_dictionary(item_value)
		var violations = _as_array(item.get("violations", []))
		if not violations.is_empty():
			continue
		if abs(top_score - float(item.get("score", 0.0))) <= tie_threshold:
			tied.append(str(item.get("id", "")))
	return tied


func _is_cast_manager_proposal(proposal: Dictionary) -> bool:
	return str(proposal.get("role", proposal.get("agent_id", ""))) == "CastManager"


func _is_on_cooldown(proposal: Dictionary, ledger: Dictionary) -> bool:
	var cooldown_key = str(proposal.get("cooldown_key", ""))
	if cooldown_key.is_empty():
		return false

	var cooldowns = ledger.get("cooldowns", {})
	if typeof(cooldowns) != TYPE_DICTIONARY:
		return false

	var current_tick = int(ledger.get("current_tick", 0))
	return int(cooldowns.get(cooldown_key, -1)) > current_tick


func _proposal_id(proposal: Dictionary, index: int) -> String:
	var proposal_id = str(proposal.get("id", ""))
	if proposal_id.is_empty():
		return "proposal_%d" % index
	return proposal_id


func _rule_dictionary(key: String) -> Dictionary:
	var value = rules.get(key, {})
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _merge_dictionaries(base: Dictionary, patch: Dictionary) -> Dictionary:
	for key in patch.keys():
		var patch_value = patch[key]
		if base.has(key) and typeof(base[key]) == TYPE_DICTIONARY and typeof(patch_value) == TYPE_DICTIONARY:
			var base_child = _as_dictionary(base[key])
			var patch_child = _as_dictionary(patch_value)
			base[key] = _merge_dictionaries(base_child, patch_child)
		else:
			base[key] = patch_value
	return base


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _as_array(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value


func _join_strings(values: Array, separator: String) -> String:
	var parts = PackedStringArray()
	for value in values:
		parts.append(str(value))
	return separator.join(parts)


func _sort_by_score_descending(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
