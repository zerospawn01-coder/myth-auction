extends RefCounted
class_name ResearchState

const ResearchProjectScript = preload("res://scripts/research/research_project.gd")
const ObservationRecordScript = preload("res://scripts/research/observation_record.gd")
const EvidenceRecordScript = preload("res://scripts/research/evidence_record.gd")
const HypothesisRecordScript = preload("res://scripts/research/hypothesis_record.gd")

const OBSERVATION_VERBS = ["OBSERVE", "MEASURE", "INVESTIGATE"]
const GAME_STATE_SCHEMA_VERSION = 2

const DOCUMENTS_DB = {
	"DOC-MA001-001": {
		"title": "北部旧領祭具目録・第3版",
		"quotes": [
			"灰白色の祭祀鏡は北部の儀式で使われたが、複製画を見る限り鏡背に特殊な篆刻があったとされる。この篆刻は、精神の転写を封じる鎖の役割を担っていたという。",
			"現在市場に流通している類似品の多くは、この鏡背の篆刻が摩耗、あるいは最初から意図的に削り取られている模造品である。"
		]
	},
	"DOC-MA001-002": {
		"title": "帝国奇物競売録（45年前）",
		"quotes": [
			"ロット309：灰白色の祭祀鏡。銀合金製。黒色ガラス鏡面。鏡面を覗き込んだ者に強烈な既視感を与える。",
			"落札者の代理人より「鏡に奇妙な曇りが発生し、磨いても取れない。また落札者が自室に引きこもるようになった」との苦情あり。"
		]
	},
	"DOC-MA001-003": {
		"title": "守護鏡 of the 由来覚書",
		"quotes": [
			"これは代々我が家を不浄から守りし鏡なり。鏡面を磨くことで災いを払い、一族の行く末を見守ると伝わる。",
			"時折、鏡の中に我が祖先と思わしき影が映り込むが、これは我々を優しく監視し、正しい道を示してくれている証拠である。"
		]
	},
	"DOC-MA001-004": {
		"title": "クライン修復工房 納品書控",
		"quotes": [
			"クライン修復工房 納品書控。依頼品：灰白色の祭祀鏡（銀合金製）。処置内容：鏡背面に強固なアクリル系修復用エポキシ樹脂を注入し、亀裂部を補強・平滑化。",
			"裏面に何らかの刻印があったと見られるが、亀裂補強および平滑化の研磨作業に伴い、研磨剤によって完全に削り取られた状態であった。"
		]
	}
}

const CONTRACTORS_DB = {
	"folklorist": {
		"cost": 500
	},
	"anomaly_analyst": {
		"cost": 800
	}
}

signal project_updated(target_id: String)
signal observation_added(observation_id: String)
signal hypothesis_updated(hypothesis_id: String)
signal state_reloaded

var projects: Dictionary = {}
var observations: Dictionary = {}
var evidences: Dictionary = {}
var hypotheses: Dictionary = {}

var player_state = null
var research_claim: Dictionary = {
	"claim_text": "",
	"warrant": "",
	"evidence_ids": [],
	"unresolved_conflicts": [],
	"scope": "限定的"
}
var evidence_list: Array = []
var commission = null

var _project_id_by_target: Dictionary = {}
var _observation_id_by_ledger_hash: Dictionary = {}
var _next_hypothesis_sequence: int = 1
var _next_evidence_sequence: int = 1


func bind_player_state(bound_player_state) -> void:
	player_state = bound_player_state


func clear() -> void:
	projects.clear()
	observations.clear()
	evidences.clear()
	hypotheses.clear()
	research_claim = {
		"claim_text": "",
		"warrant": "",
		"evidence_ids": [],
		"unresolved_conflicts": [],
		"scope": "限定的"
	}
	evidence_list.clear()
	commission = null
	_project_id_by_target.clear()
	_observation_id_by_ledger_hash.clear()
	_next_hypothesis_sequence = 1
	_next_evidence_sequence = 1



func process_ledger_entry(entry: Dictionary) -> bool:
	if str(entry.get("status", "")).to_lower() != "approved":
		return false

	var action_id = str(entry.get("action_id", ""))
	var context = _as_dictionary(entry.get("context", {}))
	var payload = _as_dictionary(entry.get("payload", {}))
	var target_payload = payload if not payload.is_empty() else context

	if action_id == "act_open_document":
		return _open_document(str(entry.get("target_id", "")))
	elif action_id == "act_clip_quote":
		return _clip_quote(
			str(entry.get("target_id", "")),
			str(target_payload.get("quote", target_payload.get("selected_quote", "")))
		)
	elif action_id == "act_place_commission":
		return _place_commission(target_payload)
	elif action_id == "act_update_research_claim":
		return _update_research_claim(
			str(target_payload.get("claim_text", "")),
			str(target_payload.get("warrant", "")),
			_to_string_array(target_payload.get("evidence_ids", []))
		)

	var target_id = str(entry.get("target_id", ""))
	var ledger_hash = str(entry.get("entry_hash", ""))
	var verb = _entry_verb(entry)
	if target_id.is_empty() or ledger_hash.is_empty() or verb not in OBSERVATION_VERBS:
		return false
	if _observation_id_by_ledger_hash.has(ledger_hash):
		return false

	var project = get_or_create_project(target_id)
	if project == null:
		return false

	var observation_id = "observation:%s" % ledger_hash
	if observations.has(observation_id):
		return false

	var observation = ObservationRecordScript.new(observation_id)
	observation.target_id = target_id
	observation.ledger_hash = ledger_hash
	observation.action_id = str(entry.get("action_id", ""))
	observation.verb = verb
	observation.actor_id = str(entry.get("actor_id", ""))
	observation.summary = _entry_summary(entry, verb)
	observation.observed_at = int(entry.get("timestamp", observation.observed_at))
	observation.state = "OBSERVED"

	if verb == "OBSERVE" or observation.action_id.find("eye") != -1 or observation.action_id.find("obs") != -1:
		observation.findings = ["裏面：削り刻印検知"]
	elif verb == "MEASURE" or observation.action_id.find("residue") != -1:
		observation.findings = ["材質の不整合、古代残留物質、接着成分"]
	elif verb == "INVESTIGATE" or observation.action_id.find("resonance") != -1:
		observation.findings = ["呪的干渉効果、発動条件、温度低下傾向"]

	if not observation.is_valid():
		return false

	observations[observation_id] = observation
	_observation_id_by_ledger_hash[ledger_hash] = observation_id
	project.observation_ids.append(observation_id)
	if project.start_ledger_hash.is_empty():
		project.start_ledger_hash = ledger_hash

	observation_added.emit(observation_id)
	project_updated.emit(target_id)
	return true



func get_project_for_target(target_id: String):
	var project_id = str(_project_id_by_target.get(target_id, ""))
	if project_id.is_empty():
		return null
	return projects.get(project_id)


func get_or_create_project(target_id: String):
	if target_id.is_empty():
		return null
	var existing = get_project_for_target(target_id)
	if existing != null:
		return existing

	var project_id = "research_project:%s" % target_id
	var project = ResearchProjectScript.new(project_id)
	project.target_id = target_id
	projects[project_id] = project
	_project_id_by_target[target_id] = project_id
	return project


func create_hypothesis(target_id: String, hypothesis_text: String):
	var normalized_text = hypothesis_text.strip_edges()
	if target_id.is_empty() or normalized_text.is_empty():
		return null
	var project = get_or_create_project(target_id)
	if project == null:
		return null

	var hypothesis_id = _new_hypothesis_id()
	var hypothesis = HypothesisRecordScript.new(hypothesis_id)
	hypothesis.target_id = target_id
	hypothesis.text = normalized_text
	hypotheses[hypothesis_id] = hypothesis
	project.hypothesis_ids.append(hypothesis_id)

	hypothesis_updated.emit(hypothesis_id)
	project_updated.emit(target_id)
	return hypothesis


func attach_evidence(
	hypothesis_id: String,
	observation_id: String,
	evidence_type: String = EvidenceRecordScript.TYPE_SUPPORT,
	reliability: float = 1.0
) -> bool:
	if not hypotheses.has(hypothesis_id) or not observations.has(observation_id):
		return false
	var normalized_type = evidence_type.to_upper()
	if normalized_type not in EvidenceRecordScript.VALID_TYPES:
		return false
	if reliability != reliability or reliability <= 0.0 or reliability > 1.0:
		return false

	var hypothesis = hypotheses[hypothesis_id]
	var observation = observations[observation_id]
	if hypothesis.target_id != observation.target_id:
		return false
	for existing_evidence_id in hypothesis.evidence_ids:
		var existing_evidence = evidences.get(existing_evidence_id)
		if existing_evidence != null and existing_evidence.observation_id == observation_id:
			return false

	var evidence_id = _new_evidence_id()
	var evidence = EvidenceRecordScript.new(evidence_id)
	evidence.target_id = hypothesis.target_id
	evidence.hypothesis_id = hypothesis_id
	evidence.observation_id = observation_id
	evidence.evidence_type = normalized_type
	evidence.reliability = reliability
	if not evidence.is_valid():
		return false

	evidences[evidence_id] = evidence
	hypothesis.evidence_ids.append(evidence_id)
	var project = get_project_for_target(hypothesis.target_id)
	if project != null:
		project.evidence_ids.append(evidence_id)
	hypothesis.recompute_confidence(evidences)

	hypothesis_updated.emit(hypothesis_id)
	project_updated.emit(hypothesis.target_id)
	return true


func get_observations_for_target(target_id: String) -> Array:
	var result: Array = []
	var project = get_project_for_target(target_id)
	if project == null:
		return result
	for observation_id in project.observation_ids:
		if observations.has(observation_id):
			result.append(observations[observation_id])
	return result


func get_hypotheses_for_target(target_id: String) -> Array:
	var result: Array = []
	var project = get_project_for_target(target_id)
	if project == null:
		return result
	for hypothesis_id in project.hypothesis_ids:
		if hypotheses.has(hypothesis_id):
			result.append(hypotheses[hypothesis_id])
	return result


func to_dictionary() -> Dictionary:
	return {
		"schema_version": GAME_STATE_SCHEMA_VERSION,
		"projects": _serialize_records(projects),
		"observations": _serialize_records(observations),
		"evidences": _serialize_records(evidences),
		"hypotheses": _serialize_records(hypotheses),
		"next_hypothesis_sequence": _next_hypothesis_sequence,
		"next_evidence_sequence": _next_evidence_sequence,
		"research_claim": research_claim.duplicate(true),
		"evidence_list": evidence_list.duplicate(true),
		"commission": commission.duplicate(true) if commission != null else null
	}


func load_from_dictionary(snapshot: Dictionary) -> bool:
	if int(snapshot.get("schema_version", 1)) != GAME_STATE_SCHEMA_VERSION:
		return false
	clear()
	for key in ["projects", "observations", "evidences", "hypotheses"]:
		if typeof(snapshot.get(key, {})) != TYPE_DICTIONARY:
			clear()
			return false

	if not _load_projects(snapshot.get("projects", {})):
		clear()
		return false
	if not _load_observations(snapshot.get("observations", {})):
		clear()
		return false
	if not _load_hypotheses(snapshot.get("hypotheses", {})):
		clear()
		return false
	if not _load_evidences(snapshot.get("evidences", {})):
		clear()
		return false

	_next_hypothesis_sequence = maxi(1, int(snapshot.get("next_hypothesis_sequence", 1)))
	_next_evidence_sequence = maxi(1, int(snapshot.get("next_evidence_sequence", 1)))
	
	research_claim = _as_dictionary(snapshot.get("research_claim", {})).duplicate(true)
	evidence_list.clear()
	for card in snapshot.get("evidence_list", []):
		evidence_list.append(_as_dictionary(card).duplicate(true))
	var comm_data = snapshot.get("commission", null)
	if comm_data != null and typeof(comm_data) == TYPE_DICTIONARY:
		commission = _as_dictionary(comm_data).duplicate(true)
	else:
		commission = null

	if not _rebuild_indexes_and_validate():
		clear()
		return false

	state_reloaded.emit()
	return true


func _entry_verb(entry: Dictionary) -> String:
	var verb = str(entry.get("verb", "")).to_upper()
	if not verb.is_empty():
		return verb
	var payload = _as_dictionary(entry.get("payload", {}))
	verb = str(payload.get("verb", "")).to_upper()
	if not verb.is_empty():
		return verb
	var action = _as_dictionary(payload.get("action", {}))
	return str(action.get("verb", "")).to_upper()


func _entry_summary(entry: Dictionary, verb: String) -> String:
	var payload = _as_dictionary(entry.get("payload", {}))
	var action = _as_dictionary(payload.get("action", {}))
	var metadata = _as_dictionary(action.get("metadata", {}))
	var summary = str(metadata.get("description", metadata.get("label", ""))).strip_edges()
	if not summary.is_empty():
		return summary
	var action_id = str(entry.get("action_id", ""))
	return "%s observation from %s" % [verb, action_id]


func _new_hypothesis_id() -> String:
	var hypothesis_id = "hypothesis:%06d" % _next_hypothesis_sequence
	while hypotheses.has(hypothesis_id):
		_next_hypothesis_sequence += 1
		hypothesis_id = "hypothesis:%06d" % _next_hypothesis_sequence
	_next_hypothesis_sequence += 1
	return hypothesis_id


func _new_evidence_id() -> String:
	var evidence_id = "evidence:%06d" % _next_evidence_sequence
	while evidences.has(evidence_id):
		_next_evidence_sequence += 1
		evidence_id = "evidence:%06d" % _next_evidence_sequence
	_next_evidence_sequence += 1
	return evidence_id


func _serialize_records(records: Dictionary) -> Dictionary:
	var serialized: Dictionary = {}
	var record_ids = records.keys()
	record_ids.sort()
	for record_id in record_ids:
		var record = records[record_id]
		if record != null and record.has_method("to_dictionary"):
			serialized[str(record_id)] = record.to_dictionary()
	return serialized


func _load_projects(serialized: Dictionary) -> bool:
	for project_id_value in serialized.keys():
		var project_id = str(project_id_value)
		var data = _as_dictionary(serialized[project_id_value])
		if project_id.is_empty() or data.is_empty():
			return false
		var project = ResearchProjectScript.new(project_id)
		project.load_from_dictionary(data)
		project.project_id = project_id
		if not project.is_valid():
			return false
		projects[project_id] = project
	return true


func _load_observations(serialized: Dictionary) -> bool:
	for observation_id_value in serialized.keys():
		var observation_id = str(observation_id_value)
		var data = _as_dictionary(serialized[observation_id_value])
		if observation_id.is_empty() or data.is_empty():
			return false
		var observation = ObservationRecordScript.new(observation_id)
		observation.load_from_dictionary(data)
		observation.observation_id = observation_id
		if not observation.is_valid():
			return false
		observations[observation_id] = observation
	return true


func _load_hypotheses(serialized: Dictionary) -> bool:
	for hypothesis_id_value in serialized.keys():
		var hypothesis_id = str(hypothesis_id_value)
		var data = _as_dictionary(serialized[hypothesis_id_value])
		if hypothesis_id.is_empty() or data.is_empty():
			return false
		var hypothesis = HypothesisRecordScript.new(hypothesis_id)
		hypothesis.load_from_dictionary(data)
		hypothesis.hypothesis_id = hypothesis_id
		if not hypothesis.is_valid():
			return false
		hypotheses[hypothesis_id] = hypothesis
	return true


func _load_evidences(serialized: Dictionary) -> bool:
	for evidence_id_value in serialized.keys():
		var evidence_id = str(evidence_id_value)
		var data = _as_dictionary(serialized[evidence_id_value])
		if evidence_id.is_empty() or data.is_empty():
			return false
		var evidence = EvidenceRecordScript.new(evidence_id)
		evidence.load_from_dictionary(data)
		evidence.evidence_id = evidence_id
		if not evidence.is_valid():
			return false
		evidences[evidence_id] = evidence
	return true


func _rebuild_indexes_and_validate() -> bool:
	_project_id_by_target.clear()
	_observation_id_by_ledger_hash.clear()

	for project_id in projects.keys():
		var project = projects[project_id]
		if _project_id_by_target.has(project.target_id):
			return false
		if _has_duplicates(project.observation_ids) or _has_duplicates(project.evidence_ids) or _has_duplicates(project.hypothesis_ids):
			return false
		_project_id_by_target[project.target_id] = project_id

	for observation_id in observations.keys():
		var observation = observations[observation_id]
		if _observation_id_by_ledger_hash.has(observation.ledger_hash):
			return false
		var project = get_project_for_target(observation.target_id)
		if project == null or not project.observation_ids.has(observation_id):
			return false
		_observation_id_by_ledger_hash[observation.ledger_hash] = observation_id

	for hypothesis_id in hypotheses.keys():
		var hypothesis = hypotheses[hypothesis_id]
		if _has_duplicates(hypothesis.evidence_ids):
			return false
		var project = get_project_for_target(hypothesis.target_id)
		if project == null or not project.hypothesis_ids.has(hypothesis_id):
			return false

	for evidence_id in evidences.keys():
		var evidence = evidences[evidence_id]
		if not hypotheses.has(evidence.hypothesis_id) or not observations.has(evidence.observation_id):
			return false
		var hypothesis = hypotheses[evidence.hypothesis_id]
		var observation = observations[evidence.observation_id]
		var project = get_project_for_target(evidence.target_id)
		if hypothesis.target_id != evidence.target_id or observation.target_id != evidence.target_id:
			return false
		if project == null or not project.evidence_ids.has(evidence_id) or not hypothesis.evidence_ids.has(evidence_id):
			return false

	for project in projects.values():
		for observation_id in project.observation_ids:
			if not observations.has(observation_id) or observations[observation_id].target_id != project.target_id:
				return false
		for hypothesis_id in project.hypothesis_ids:
			if not hypotheses.has(hypothesis_id) or hypotheses[hypothesis_id].target_id != project.target_id:
				return false
		for evidence_id in project.evidence_ids:
			if not evidences.has(evidence_id) or evidences[evidence_id].target_id != project.target_id:
				return false

	for hypothesis in hypotheses.values():
		var used_observation_ids: Dictionary = {}
		for evidence_id in hypothesis.evidence_ids:
			if not evidences.has(evidence_id):
				return false
			var observation_id = evidences[evidence_id].observation_id
			if used_observation_ids.has(observation_id):
				return false
			used_observation_ids[observation_id] = true
		hypothesis.recompute_confidence(evidences)
	return true


func _has_duplicates(values: Array[String]) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value):
			return true
		seen[value] = true
	return false


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _to_string_array(value) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_STRING_ARRAY:
		for item in value:
			result.append(str(item))
	return result


func _open_document(doc_id: String) -> bool:
	if player_state == null:
		return false
	if not player_state.is_document_unlocked(doc_id):
		return false
	player_state.read_document(doc_id)
	return true


func _clip_quote(doc_id: String, quote: String) -> bool:
	if player_state == null:
		return false
	if not DOCUMENTS_DB.has(doc_id):
		return false
	if not player_state.is_document_unlocked(doc_id) or not player_state.is_document_read(doc_id):
		return false
	var quotes = DOCUMENTS_DB[doc_id].get("quotes", [])
	if not quotes.has(quote):
		return false

	var evidence_id = "EVID-CLIP-%s-%d" % [doc_id, hash(quote)]
	var already_clipped = false
	for card in evidence_list:
		if card.get("evidence_id", "") == evidence_id:
			already_clipped = true
			break
	if not already_clipped:
		var card = {
			"evidence_id": evidence_id,
			"source_id": doc_id,
			"source_title": DOCUMENTS_DB[doc_id].get("title", ""),
			"quote": quote,
			"source_type": "DOCUMENT",
			"diagnosis_tags": [],
			"player_relation": "SUPPORT"
		}
		evidence_list.append(card)
	return true


func _place_commission(order: Dictionary) -> bool:
	if player_state == null:
		return false
	var breakdown = get_commission_cost_breakdown(order)
	if breakdown == null:
		return false
	var total_cost = int(breakdown.get("totalCost", 0))
	var gold_balance = player_state.get_resource("gold")
	if gold_balance < total_cost:
		return false

	player_state.modify_resource("gold", -total_cost)
	commission = order.duplicate(true)
	commission["status"] = "PENDING"
	commission["cost_breakdown"] = breakdown
	return true


func _update_research_claim(claim_text: String, warrant: String, evidence_ids: Array[String]) -> bool:
	research_claim["claim_text"] = claim_text
	research_claim["warrant"] = warrant
	research_claim["evidence_ids"] = evidence_ids.duplicate()
	return true


func get_commission_cost_breakdown(order: Dictionary):
	if order.is_empty():
		return null
	var contractor_id = str(order.get("contractor_id", ""))
	if not CONTRACTORS_DB.has(contractor_id):
		return null
	var contractor = CONTRACTORS_DB[contractor_id]

	var custody_controls = _as_dictionary(order.get("custody_controls", {}))
	var permitted_actions = _as_dictionary(order.get("permitted_actions", {}))

	if (
		typeof(custody_controls.get("sealRegistered", false)) != TYPE_BOOL or
		typeof(custody_controls.get("weightRecorded", false)) != TYPE_BOOL or
		typeof(custody_controls.get("sampleSaved", false)) != TYPE_BOOL or
		typeof(permitted_actions.get("allowDestructive", false)) != TYPE_BOOL or
		not str(permitted_actions.get("budget", "")) in ["low", "medium", "high"] or
		not str(permitted_actions.get("secrecyLevel", "")) in ["low", "high"]
	):
		return null

	var seal = bool(custody_controls.get("sealRegistered", false))
	var weight = bool(custody_controls.get("weightRecorded", false))
	var sample = bool(custody_controls.get("sampleSaved", false))
	var destructive = bool(permitted_actions.get("allowDestructive", false))
	var secrecy = str(permitted_actions.get("secrecyLevel", ""))

	var audit_cost = (150 if seal else 0) + (100 if weight else 0) + (200 if sample else 0)
	var secrecy_modifier = 100 if secrecy == "high" else 0
	var destructive_modifier = -100 if destructive else 0
	var total_cost = contractor["cost"] + audit_cost + secrecy_modifier + destructive_modifier

	return {
		"baseCost": contractor["cost"],
		"auditCost": audit_cost,
		"secrecyModifier": secrecy_modifier,
		"destructiveModifier": destructive_modifier,
		"totalCost": total_cost
	}

