## Myth Capability Resolver — M54 Typed Capability Resolver v0.1
##
## Connects Subject properties, Contact capabilities, and Tool capabilities
## to deterministic ActionCandidate generation, ActionGate validation,
## and M53 ActionIntent pipeline execution.

const ActionGateScript = preload("res://scripts/mvp/action_gate.gd")
const PredicateEvaluatorScript = preload("res://scripts/mvp/case_predicate_evaluator.gd")
const ActionSlotDefinitionScript = preload("res://scripts/actions/action_slot_definition.gd")
const SemanticRoleScript = preload("res://scripts/actions/semantic_role.gd")
const MissingRequirementScript = preload("res://scripts/actions/missing_requirement.gd")

const UNOBSERVED := "UNOBSERVED"
const HIDDEN     := "HIDDEN"
const DISCOVERED := "DISCOVERED"
const LOCKED     := "LOCKED"
const AVAILABLE  := "AVAILABLE"

var _evaluator = PredicateEvaluatorScript.new()


## Factory for ActionSlotDefinition
static func create_slot_definition(
	slot_id: String,
	role: String,
	required: bool = true,
	required_properties: Array = [],
	required_capabilities: Array = [],
	domain_matching: bool = false
) -> Object:
	var slot = ActionSlotDefinitionScript.new()
	var entity_kind := "SUBJECT"
	if role == "contact": entity_kind = "CONTACT"
	elif role == "tool": entity_kind = "TOOL"
	elif role == "observation_method": entity_kind = "OBSERVATION_METHOD"
	elif role in ["observation", "source_observation"]: entity_kind = "OBSERVATION"
	elif role in ["evidence", "source_evidence"]: entity_kind = "EVIDENCE"
	slot.load_from_dictionary({
		"slot_id": slot_id,
		"semantic_role_id": role,
		"role": role,
		"entity_kind": entity_kind,
		"min_count": 1 if required else 0,
		"max_count": 1,
		"allow": "ALLOW",
		"required_properties": required_properties.duplicate(true),
		"required_capabilities": required_capabilities.duplicate(true),
		"discovery_state": "DISCOVERED",
		"description": "slot definition for %s" % role,
		"domain_matching": domain_matching
	})
	return slot


## Factory for structured MissingRequirement
static func create_missing_requirement(
	role: String,
	requirement_type: String,
	missing_value: String,
	remediation_hint: String
) -> Dictionary:
	var requirement = MissingRequirementScript.new()
	requirement.load_from_dictionary({
		"role": role,
		"requirement_type": requirement_type,
		"missing_value": missing_value,
		"remediation_hint": remediation_hint
	})
	return requirement.to_dictionary()


## Build deterministic canonical_action_key from action_id, route_id, and entity bindings
static func build_canonical_action_key(action_id: String, bindings: Dictionary, route_id: String = "") -> String:
	var key_parts: Array[String] = [action_id]
	if not route_id.is_empty():
		key_parts.append("route:%s" % route_id)
	var roles: Array = bindings.keys()
	roles.sort()
	for role in roles:
		if bindings.has(role):
			var entity: Dictionary = bindings[role] if typeof(bindings[role]) == TYPE_DICTIONARY else {}
			var entity_id := str(entity.get("id", entity.get("lot_id", entity.get("contractor_id", entity.get("observation_id", entity.get("evidence_id", "none"))))))
			key_parts.append("%s:%s" % [role, entity_id])
	return "|".join(key_parts)


## Resolve all candidates for a given state.
## Returns Array[Dictionary] of candidates, sorted deterministically by canonical_action_key.
## Candidates with DiscoveryState == HIDDEN or UNOBSERVED are excluded from visible output.
func resolve_candidates(state, custom_action_templates: Array = []) -> Array:
	if state == null:
		return []

	var subjects := _extract_subjects(state)
	var contacts := _extract_contacts(state)
	var tools    := _extract_tools(state)
	var observation_methods := _extract_observation_methods(state)
	var observations := _extract_observations(state)
	var evidence_cards := _extract_evidence_cards(state)
	var templates := _get_action_templates(state, custom_action_templates)

	var candidates_by_key: Dictionary = {}

	for template in templates:
		var action_id := str(template.get("action_id", ""))
		if action_id.is_empty():
			continue

		# Evaluate overall discovery state / preconditions for template
		var template_disc := _evaluate_discovery_state(template, state)
		if template_disc == HIDDEN or template_disc == UNOBSERVED:
			continue

		var slots: Array = _normalize_template_slots(template.get("slots", []))
		var semantic_roles: Array = _normalize_template_semantic_roles(template.get("semantic_roles", []))

		# Find entity options per slot
		var slot_options: Dictionary = {}
		var slot_missing_reqs: Array = []
		var is_locked_by_slot := false

		for slot in slots:
			var slot_dict: Dictionary = _as_dict(slot)
			var slot_id := str(slot_dict.get("slot_id", ""))
			var role := str(slot_dict.get("role", slot_dict.get("semantic_role_id", slot_dict.get("role_id", slot_id))))
			var is_req := bool(slot_dict.get("required", true)) or int(slot_dict.get("min_count", 0)) > 0

			var matching_entities := _find_matching_entities(slot_dict, subjects, contacts, tools, observation_methods, observations, evidence_cards)

			if matching_entities.is_empty():
				if is_req:
					is_locked_by_slot = true
					# Generate structured missing requirement
					slot_missing_reqs.append_array(_build_slot_missing_requirements(slot_dict))
				# For empty slot, place a dummy placeholder so combination loop produces a candidate binding
				slot_options[slot_id] = [{}]
			else:
				slot_options[slot_id] = matching_entities
				if not is_req:
					slot_options[slot_id].push_front({})

		# Enumerate cartesian product of slot options
		var combinations := _enumerate_combinations(slots, slot_options)

		var route_id := str(template.get("route_id", ""))
		for comb in combinations:
			var bindings: Dictionary = comb
			var canonical_key := build_canonical_action_key(action_id, bindings, route_id)

			var missing_reqs: Array = slot_missing_reqs.duplicate(true)
			var discovery := template_disc

			if is_locked_by_slot:
				discovery = LOCKED
			else:
				# Validate domain matching between subject and contact
				var domain_err := _check_domain_matching(slots, bindings)
				if not domain_err.is_empty():
					missing_reqs.append(domain_err)
					discovery = LOCKED

			# Distinct participant check (e.g. primary_subject vs comparison_subject)
			var p_sub_id := str(_as_dict(bindings.get("primary_subject", {})).get("id", ""))
			var c_sub_id := str(_as_dict(bindings.get("comparison_subject", {})).get("id", ""))
			if not p_sub_id.is_empty() and not c_sub_id.is_empty() and p_sub_id == c_sub_id:
				discovery = LOCKED
				missing_reqs.append(create_missing_requirement(
					"comparison_subject",
					"distinct_participant_required",
					p_sub_id,
					"select_different_comparison_subject"
				))

			# Closed or Lost subject relation check
			for role_name in bindings:
				var entity: Dictionary = _as_dict(bindings[role_name])
				var kind := _entity_kind_for_role(slots, str(role_name))
				if kind == "SUBJECT":
					var rel_state := str(entity.get("relation_state", ""))
					if rel_state in ["CLOSED", "LOST"]:
						discovery = LOCKED
						missing_reqs.append(create_missing_requirement(
							str(role_name),
							"subject_closed_or_lost",
							rel_state,
							"subject_relation_inactive"
						))

			# Evaluate template predicates against bound context & facts
			if discovery != LOCKED:
				var context_facts := _build_facts_and_context(state, bindings)
				var preds = template.get("predicates", {})
				if not preds.is_empty():
					var ok := _evaluator.evaluate(preds, context_facts["facts"], context_facts["context"])
					if not ok:
						discovery = LOCKED
						missing_reqs.append(create_missing_requirement(
							"predicate",
							"predicate_failed",
							str(_evaluator.last_error),
							"satisfy_action_predicates"
						))

			# Resource / ActionGate evaluation
			var candidate_resource_cost := _candidate_resource_cost(template, bindings)
			var intent_preview := _candidate_to_intent_preview(template, bindings, state, candidate_resource_cost)
			var gate_res := ActionGateScript.check(intent_preview, state, state.resolver if state != null else null)
			if not bool(gate_res.get("allowed", false)):
				if discovery == AVAILABLE or discovery == DISCOVERED:
					discovery = LOCKED
				missing_reqs.append(create_missing_requirement(
					"gate",
					"gate_denied",
					str(gate_res.get("reason", "")),
					str(gate_res.get("gate_id", "RESOURCE_GATE"))
				))

			if discovery == DISCOVERED and missing_reqs.is_empty():
				discovery = AVAILABLE

			# Build participant list
			var participants: Array = []
			for role_name in bindings:
				var entity: Dictionary = bindings[role_name]
				var entity_id := str(entity.get("id", entity.get("lot_id", entity.get("contractor_id", ""))))
				if not entity_id.is_empty():
					var kind := _entity_kind_for_role(slots, str(role_name))
					participants.append({
						"entity_kind": kind,
						"entity_id": entity_id,
						"semantic_role": role_name
					})

			var candidate := {
				"canonical_action_key": canonical_key,
				"action_id": action_id,
				"route_id": route_id,
				"label_key": str(template.get("label_key", "action." + action_id)),
				"verb": str(template.get("verb", action_id)),
				"discovery_state": discovery,
				"bindings": bindings.duplicate(true),
				"participants": participants,
				"missing_requirements": missing_reqs,
				"gate_result": _build_gate_result(gate_res, missing_reqs, state),
				"effects": template.get("effects", []).duplicate(true),
				"effect_contract_id": str(template.get("effect_contract_id", "")),
				"resource_cost": candidate_resource_cost,
				"context": _build_candidate_context(template, bindings),
				"semantic_roles": _snapshot_semantic_roles(semantic_roles)
			}
			candidates_by_key[canonical_key] = candidate

	var candidates: Array = []
	for key in candidates_by_key.keys():
		candidates.append(candidates_by_key[key])
	candidates.sort_custom(Callable(self, "_sort_candidates"))
	return candidates

## Convert an AVAILABLE candidate into an M53 ActionIntent dictionary
static func candidate_to_intent(candidate: Dictionary, state) -> Dictionary:
	if str(candidate.get("discovery_state", "")) != AVAILABLE:
		return {}
	var action_id := str(candidate.get("action_id", ""))
	var participants: Array = candidate.get("participants", []).duplicate(true)
	var effects: Array = candidate.get("effects", []).duplicate(true)
	var context: Dictionary = candidate.get("context", {}).duplicate(true)
	var resource_cost: Dictionary = candidate.get("resource_cost", {}).duplicate(true)
	var compiled := _compile_resource_cost_effects(effects, resource_cost)
	if not bool(compiled.get("ok", false)):
		return {}

	return {
		"action_id": action_id,
		"participants": participants,
		"effects": compiled.get("effects", []),
		"context": context,
		"resource_cost": resource_cost
		,"effect_contract_id": str(candidate.get("effect_contract_id", ""))
	}


## resource_cost is the canonical cost declaration. Candidate conversion compiles
## it into effects for M53. An explicitly supplied adjustment is accepted only
## when it agrees exactly; drift or duplicate deductions fail closed.
static func _compile_resource_cost_effects(source_effects: Array, resource_cost: Dictionary) -> Dictionary:
	var effects := source_effects.duplicate(true)
	var axes: Array = resource_cost.keys()
	axes.sort()
	for axis_value in axes:
		var axis := str(axis_value)
		var expected_delta := -int(resource_cost.get(axis, 0))
		if expected_delta > 0:
			return {"ok": false, "effects": []}
		var matching_indices: Array[int] = []
		for index in range(effects.size()):
			var effect: Dictionary = effects[index] if typeof(effects[index]) == TYPE_DICTIONARY else {}
			if str(effect.get("op", "")) == "ADJUST_RESOURCE" and str(effect.get("axis", "")) == axis:
				matching_indices.append(index)
		if matching_indices.size() > 1:
			return {"ok": false, "effects": []}
		if matching_indices.size() == 1:
			var existing: Dictionary = effects[matching_indices[0]]
			if int(existing.get("delta", 0)) != expected_delta:
				return {"ok": false, "effects": []}
		elif expected_delta != 0:
			effects.append({"op": "ADJUST_RESOURCE", "axis": axis, "delta": expected_delta})
	return {"ok": true, "effects": effects}


# ── Internal Extraction Helpers ───────────────────────────────────────────────

func _extract_subjects(state) -> Array:
	var subjects: Array = []
	var subject_ids_seen := {}

	if state == null:
		return subjects

	if state.lot_state != null and not state.lot_state.is_empty():
		var lot_copy: Dictionary = state.lot_state.duplicate(true)
		var s_id := str(lot_copy.get("id", lot_copy.get("lot_id", "primary_lot")))
		lot_copy["id"] = s_id
		lot_copy["lot_id"] = s_id
		var rel: Dictionary = _as_dict(state.subject_relations.get(s_id, {}))
		var maturity_flags: Array = _to_str_array(rel.get("maturity_flags", []))
		var props := _to_str_array(lot_copy.get("properties", []))
		var hazard_tags := _to_str_array(lot_copy.get("known_hazard_tags", []))
		for tag in hazard_tags:
			if not props.has(tag):
				props.append(tag)
		for flag in maturity_flags:
			if not props.has(flag):
				props.append(flag)
		lot_copy["properties"] = props
		lot_copy["maturity_flags"] = maturity_flags
		lot_copy["relation_state"] = str(rel.get("relation_state", "NEW"))
		subjects.append(lot_copy)
		subject_ids_seen[s_id] = true

	if typeof(state.subject_relations) == TYPE_DICTIONARY:
		for s_id in state.subject_relations.keys():
			var id_str := str(s_id)
			if not subject_ids_seen.has(id_str):
				var rel: Dictionary = _as_dict(state.subject_relations[id_str])
				var maturity_flags: Array = _to_str_array(rel.get("maturity_flags", []))
				subjects.append({
					"id": id_str,
					"lot_id": id_str,
					"domain": "general",
					"properties": maturity_flags,
					"maturity_flags": maturity_flags,
					"relation_state": str(rel.get("relation_state", "ACTIVE"))
				})
				subject_ids_seen[id_str] = true

	if state.resolver != null:
		var extra_subs: Array = _get_collection_or_package(state.resolver, "subjects")
		for doc in extra_subs:
			var dict := _as_dict(doc)
			var s_id := str(dict.get("id", dict.get("lot_id", "")))
			if not s_id.is_empty() and not subject_ids_seen.has(s_id):
				subjects.append(dict)
				subject_ids_seen[s_id] = true
	return subjects


func _extract_observations(state) -> Array:
	var list: Array = []
	if state == null or typeof(state.observations) != TYPE_DICTIONARY:
		return list
	for obs_id in state.observations.keys():
		var obs: Dictionary = _as_dict(state.observations[obs_id]).duplicate(true)
		if not obs.has("id"):
			obs["id"] = str(obs.get("observation_id", obs_id))
		list.append(obs)
	return list


func _extract_evidence_cards(state) -> Array:
	var list: Array = []
	if state == null or typeof(state.evidence_cards) != TYPE_DICTIONARY:
		return list
	for ev_id in state.evidence_cards.keys():
		var card: Dictionary = _as_dict(state.evidence_cards[ev_id]).duplicate(true)
		if not card.has("id"):
			card["id"] = str(card.get("evidence_id", ev_id))
		list.append(card)
	return list



func _extract_contacts(state) -> Array:
	var contacts: Array = []
	if state.resolver != null:
		var raw_contacts: Array = _get_collection_or_package(state.resolver, "contractors")
		if raw_contacts.is_empty():
			raw_contacts = _get_collection_or_package(state.resolver, "contacts")
		for contractor in raw_contacts:
			var c: Dictionary = _as_dict(contractor).duplicate(true)
			if not c.has("id"):
				c["id"] = str(c.get("contractor_id", ""))
			if not c.has("supported_domains"):
				c["supported_domains"] = _to_str_array(c.get("domains", [c.get("domain", "general")]))
			else:
				c["supported_domains"] = _to_str_array(c.get("supported_domains", []))
			contacts.append(c)
	return contacts


func _extract_tools(state) -> Array:
	var tools: Array = []
	if state.resolver != null:
		var raw_tools: Array = _get_collection_or_package(state.resolver, "tools")
		for t in raw_tools:
			tools.append(_as_dict(t))
	return tools


func _extract_observation_methods(state) -> Array:
	var methods: Array = []
	if state == null or state.resolver == null:
		return methods
	for value in _get_collection_or_package(state.resolver, "observation_methods"):
		var method := _as_dict(value)
		var method_id := str(method.get("id", ""))
		if method_id.is_empty() or str(state.observation_states.get(method_id, "")) == "COMMITTED":
			continue
		method["capabilities"] = ["observation_method"]
		methods.append(method)
	return methods


func _get_collection_or_package(resolver_obj, key: String) -> Array:
	if resolver_obj == null:
		return []
	if resolver_obj.has_method("get_collection"):
		var col = resolver_obj.get_collection(key)
		if typeof(col) == TYPE_ARRAY and not (col as Array).is_empty():
			return col
	if resolver_obj.package != null and typeof(resolver_obj.package) == TYPE_DICTIONARY:
		var pkg_val = resolver_obj.package.get(key, [])
		if typeof(pkg_val) == TYPE_ARRAY:
			return pkg_val
	return []


func _get_action_templates(state, custom_templates: Array) -> Array:
	var templates: Array = []
	if not custom_templates.is_empty():
		templates.append_array(custom_templates)
	else:
		var package_templates := _get_collection_or_package(state.resolver, "action_definitions") if state != null and state.resolver != null else []
		if not package_templates.is_empty():
			return package_templates
		# A loaded case package is authoritative. Falling back to MA-001-shaped
		# builtin contracts here leaks semantic actions into packages that did not
		# declare them. Builtins remain available only to isolated synthetic tests.
		if state != null and not str(state.episode_id).is_empty() and state.resolver != null and state.resolver.package != null and state.resolver.package.has("action_definitions"):
			return []
		# Builtin default templates for MVP actions
		templates.append({
			"action_id": "ANALYZE_SIGNAL",
			"verb": "analyze_signal",
			"label_key": "action.analyze_signal",
			"slots": [
				create_slot_definition("primary_subject", "primary_subject", true, ["SIGNAL_EMITTER"]),
				create_slot_definition("contact", "contact", true, [], ["signal_analysis"], true),
				create_slot_definition("tool", "tool", true, [], ["frequency_scanner"], false)
			],
			"predicates": {},
			"effects": [],
			"effect_contract_id": "CREATE_SIGNAL_ANALYSIS",
			"resource_cost": {"gold": 300}
		})
		templates.append({
			"action_id": "commission",
			"verb": "commission",
			"label_key": "action.commission",
			"slots": [
				create_slot_definition("primary_subject", "primary_subject", true, []),
				create_slot_definition("contact", "contact", true, [], [], false)
			],
			"predicates": {"predicate": "lot_status_is", "value": "RECEIVED"},
			"effects": [],
			"effect_contract_id": "CREATE_COMMISSION_ORDER",
			"resource_cost": {"gold": 500}
		})
		templates.append({
			"action_id": "observe",
			"verb": "observe",
			"label_key": "action.observe",
			"slots": [
				create_slot_definition("primary_subject", "primary_subject", true, []),
				create_slot_definition("observation_method", "observation_method", true, [])
			],
			"predicates": {"predicate": "lot_status_is", "value": "RECEIVED"},
			"effects": [],
			"effect_contract_id": "CREATE_OBSERVATION",
			"resource_cost": {}
		})
	return templates


func _find_matching_entities(slot: Dictionary, subjects: Array, contacts: Array, tools: Array, observation_methods: Array = [], observations: Array = [], evidence_cards: Array = []) -> Array:
	var role := str(slot.get("role", slot.get("semantic_role_id", slot.get("role_id", ""))))
	var entity_kind := str(slot.get("entity_kind", "")).to_upper()
	var req_props := _to_str_array(slot.get("required_properties", []))
	var req_caps  := _to_str_array(slot.get("required_capabilities", []))

	var candidates_pool: Array = []
	match entity_kind:
		"SUBJECT":
			candidates_pool = subjects
		"CONTACT":
			candidates_pool = contacts
		"TOOL":
			candidates_pool = tools
		"OBSERVATION_METHOD":
			candidates_pool = observation_methods
		"OBSERVATION":
			candidates_pool = observations
		"EVIDENCE":
			candidates_pool = evidence_cards
		_:
			candidates_pool = subjects + contacts + tools + observation_methods + observations + evidence_cards

	var matched: Array = []
	for entity in candidates_pool:
		var ent_dict: Dictionary = _as_dict(entity)
		var ent_props := _to_str_array(ent_dict.get("properties", ent_dict.get("tags", ent_dict.get("known_hazard_tags", []))))
		var ent_caps  := _to_str_array(ent_dict.get("capabilities", []))

		var props_ok := true
		for p in req_props:
			if not ent_props.has(p):
				props_ok = false
				break

		var caps_ok := true
		for c in req_caps:
			if not ent_caps.has(c):
				caps_ok = false
				break

		if props_ok and caps_ok:
			matched.append(ent_dict)

	return matched

func _normalize_template_slots(values) -> Array:
	var result: Array = []
	for slot_value in _as_array(values):
		if slot_value == null:
			continue
		if typeof(slot_value) != TYPE_DICTIONARY and slot_value.has_method("is_valid"):
			if bool(slot_value.call("is_valid")):
				result.append(slot_value)
			continue
		var slot = ActionSlotDefinitionScript.new()
		slot.load_from_dictionary(_as_dict(slot_value))
		if slot.is_valid():
			result.append(slot)
	return result

func _normalize_template_semantic_roles(values) -> Array:
	var result: Array = []
	for role_value in _as_array(values):
		if role_value == null:
			continue
		if typeof(role_value) != TYPE_DICTIONARY and role_value.has_method("is_valid"):
			if bool(role_value.call("is_valid")):
				result.append(role_value)
			continue
		var role = SemanticRoleScript.new()
		role.load_from_dictionary(_as_dict(role_value))
		if role.is_valid():
			result.append(role)
	return result

func _snapshot_semantic_roles(values) -> Array:
	var result: Array = []
	for role in _as_array(values):
		if typeof(role) == TYPE_DICTIONARY:
			result.append(role.duplicate(true))
		elif role != null and role.has_method("to_dictionary"):
			result.append(role.call("to_dictionary"))
		elif role != null:
			result.append(role)
	return result


func _check_domain_matching(slots: Array, bindings: Dictionary) -> Dictionary:
	var primary_sub: Dictionary = bindings.get("primary_subject", {})
	var contact: Dictionary = bindings.get("contact", {})

	if primary_sub.is_empty() or contact.is_empty():
		return {}

	var sub_domain := str(primary_sub.get("domain", primary_sub.get("category", "")))
	if sub_domain.is_empty():
		return {}

	# Check if slot requires domain matching
	var needs_domain_matching := false
	for slot_val in slots:
		var slot: Dictionary = _as_dict(slot_val)
		if str(slot.get("role", "")) == "contact" and bool(slot.get("domain_matching", false)):
			needs_domain_matching = true
			break

	if not needs_domain_matching:
		return {}

	var supported := _to_str_array(contact.get("supported_domains", contact.get("domains", [])))
	if not supported.has(sub_domain) and not supported.has("general") and not supported.is_empty():
		return create_missing_requirement(
			"contact",
			"domain_mismatch",
			sub_domain,
			"select_contact_matching_domain_" + sub_domain
		)

	return {}


func _build_slot_missing_requirements(slot: Dictionary) -> Array:
	var reqs: Array = []
	var role := str(slot.get("role", slot.get("semantic_role_id", slot.get("role_id", ""))))
	for p in _to_str_array(slot.get("required_properties", [])):
		reqs.append(create_missing_requirement(role, "missing_property", p, "add_property_" + p))
	for c in _to_str_array(slot.get("required_capabilities", [])):
		reqs.append(create_missing_requirement(role, "missing_capability", c, "acquire_capability_" + c))
	if reqs.is_empty():
		reqs.append(create_missing_requirement(role, "missing_entity", role, "provide_" + role))
	return reqs


func _evaluate_discovery_state(template: Dictionary, state) -> String:
	var explicit := str(template.get("discovery_state", "")).to_upper()
	if explicit in [HIDDEN, UNOBSERVED, "HINTED", DISCOVERED]:
		return explicit
	if bool(template.get("hidden", false)):
		return HIDDEN
	if bool(template.get("unobserved", false)):
		return UNOBSERVED
	return DISCOVERED


func _enumerate_combinations(slots: Array, slot_options: Dictionary) -> Array:
	if slots.is_empty():
		return [{}]

	var result: Array = [{}]
	for slot_val in slots:
		var slot: Dictionary = _slot_to_dictionary(slot_val)
		var slot_id := str(slot.get("slot_id", ""))
		var role := str(slot.get("role", slot.get("semantic_role_id", slot_id)))
		var options: Array = slot_options.get(slot_id, [{}])

		var next_result: Array = []
		for existing_comb_val in result:
			var existing_comb: Dictionary = _as_dict(existing_comb_val)
			for opt_val in options:
				var new_comb := existing_comb.duplicate(true)
				var opt_dict: Dictionary = _as_dict(opt_val)
				if not opt_dict.is_empty():
					new_comb[role] = opt_dict
				next_result.append(new_comb)
		result = next_result

	return result


func _build_facts_and_context(state, bindings: Dictionary) -> Dictionary:
	var facts := {
		"lot_state": state.lot_state if state != null else {},
		"observations": state.observations if state != null else {},
		"claim": state.claim if state != null else {},
		"listing": state.listing if state != null else {},
		"resources": state.resources if state != null else {},
		"case_tags": _to_str_array(state.resolver.get_package_section("case_metadata").get("tags", [])) if state != null and state.resolver != null else []
	}
	var context := bindings.duplicate(true)
	if bindings.has("primary_subject"):
		context["subject"] = bindings["primary_subject"]
		context["subject_domain"] = str(bindings["primary_subject"].get("domain", ""))
	return {"facts": facts, "context": context}


func _candidate_to_intent_preview(template: Dictionary, bindings: Dictionary, state, resolved_cost: Dictionary = {}) -> Dictionary:
	var action_id := str(template.get("action_id", ""))
	var cost: Dictionary = resolved_cost.duplicate(true) if not resolved_cost.is_empty() else template.get("resource_cost", {}).duplicate(true)
	return {
		"action_id": action_id,
		"resource_cost": cost,
		"context": bindings
	}


func _candidate_resource_cost(template: Dictionary, bindings: Dictionary) -> Dictionary:
	var cost: Dictionary = template.get("resource_cost", {}).duplicate(true)
	var method: Dictionary = bindings.get("observation_method", {}) if typeof(bindings.get("observation_method", {})) == TYPE_DICTIONARY else {}
	var method_cost = method.get("cost", null)
	if typeof(method_cost) == TYPE_DICTIONARY:
		var resource_id := str(method_cost.get("resource_id", "gold"))
		var amount := int(method_cost.get("amount", 0))
		if amount > 0:
			cost[resource_id] = amount
	elif method_cost != null:
		var normalized_amount := int(method_cost)
		if normalized_amount > 0:
			cost[str(method.get("cost_resource_id", "gold"))] = normalized_amount
	return cost


func _build_candidate_context(template: Dictionary, bindings: Dictionary) -> Dictionary:
	var ctx := bindings.duplicate(true)
	if template.has("context"):
		var t_ctx: Dictionary = _as_dict(template.get("context", {}))
		ctx.merge(t_ctx, true)
	var contract_id := str(template.get("effect_contract_id", ""))
	match contract_id:
		"REEXAMINE_SUBJECT":
			if bindings.has("primary_subject"):
				ctx["subject_id"] = str(_as_dict(bindings["primary_subject"]).get("id", ""))
			if bindings.has("observation_method"):
				ctx["observation_method_id"] = str(_as_dict(bindings["observation_method"]).get("id", ""))
		"COMPARE_SUBJECTS":
			var subs: Array = []
			if bindings.has("primary_subject"):
				subs.append(str(_as_dict(bindings["primary_subject"]).get("id", "")))
			if bindings.has("comparison_subject"):
				subs.append(str(_as_dict(bindings["comparison_subject"]).get("id", "")))
			ctx["comparison_subjects"] = subs
		"REPLICATE_OBSERVATION":
			if bindings.has("source_observation"):
				ctx["source_observation_id"] = str(_as_dict(bindings["source_observation"]).get("id", ""))
			elif bindings.has("observation"):
				ctx["source_observation_id"] = str(_as_dict(bindings["observation"]).get("id", ""))
		"REINTERPRET_EVIDENCE":
			if bindings.has("source_evidence"):
				ctx["source_evidence_id"] = str(_as_dict(bindings["source_evidence"]).get("id", ""))
			elif bindings.has("evidence"):
				ctx["source_evidence_id"] = str(_as_dict(bindings["evidence"]).get("id", ""))
			if bindings.has("contact"):
				ctx["reinterpretation_basis"] = {"contact_id": str(_as_dict(bindings["contact"]).get("id", ""))}
			elif bindings.has("tool"):
				ctx["reinterpretation_basis"] = {"tool_id": str(_as_dict(bindings["tool"]).get("id", ""))}
	return ctx


func _sort_candidates(a: Dictionary, b: Dictionary) -> bool:
	var key_a := str(a.get("canonical_action_key", ""))
	var key_b := str(b.get("canonical_action_key", ""))
	return key_a < key_b


func _as_dict(val) -> Dictionary:
	if typeof(val) == TYPE_DICTIONARY:
		return val.duplicate(true)
	if val != null and val.has_method("to_dictionary"):
		var snapshot = val.call("to_dictionary")
		if typeof(snapshot) == TYPE_DICTIONARY:
			return snapshot.duplicate(true)
	return {}


func _as_array(val) -> Array:
	return val if typeof(val) == TYPE_ARRAY else []

func _slot_to_dictionary(slot_val) -> Dictionary:
	return _as_dict(slot_val)

func _to_str_array(val) -> Array[String]:
	var res: Array[String] = []
	if typeof(val) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		for x in val:
			res.append(str(x))
	return res


func _build_gate_result(gate_result: Dictionary, missing: Array, state) -> Dictionary:
	var reason_codes: Array = []
	if not bool(gate_result.get("allowed", false)):
		reason_codes.append(str(gate_result.get("gate_id", "UNKNOWN_GATE")))
	for requirement in missing:
		var requirement_dict := _as_dict(requirement)
		var code := str(requirement_dict.get("requirement_type", ""))
		if not code.is_empty() and not reason_codes.has(code):
			reason_codes.append(code)
	var remediations: Array = []
	for requirement in missing:
		var hint := str(_as_dict(requirement).get("remediation_hint", ""))
		if not hint.is_empty() and not remediations.has(hint):
			remediations.append(hint)
	return {
		"allowed": bool(gate_result.get("allowed", false)) and missing.is_empty(),
		"reason": str(gate_result.get("reason", "")),
		"gate_id": str(gate_result.get("gate_id", "")),
		"reason_codes": reason_codes,
		"missing_requirements": missing.duplicate(true),
		"remediation_action_ids": remediations,
		"evaluated_revision": int(state.tick) if state != null else -1
	}


func _entity_kind_for_role(slots: Array, role_id: String) -> String:
	for slot_value in slots:
		var slot := _as_dict(slot_value)
		var candidate_role := str(slot.get("role", slot.get("semantic_role_id", slot.get("role_id", ""))))
		if candidate_role == role_id:
			var kind := str(slot.get("entity_kind", "SUBJECT")).to_upper()
			return kind if kind in ["SUBJECT", "CONTACT", "TOOL"] else "SUBJECT"
	return "SUBJECT"
