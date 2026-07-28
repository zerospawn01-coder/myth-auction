extends RefCounted
class_name HazardProjector

const PROJECTOR_VERSION := 1


func project(lot_state: Dictionary, observations: Dictionary, current_tick: int) -> Dictionary:
	var phenomenon_ids: Array[String] = []
	var sources: Array[Dictionary] = []
	var observation_ids := observations.keys()
	observation_ids.sort_custom(func(a, b): return str(a) < str(b))
	for observation_id_value in observation_ids:
		var observation_id := str(observation_id_value)
		var observation := _dictionary(observations.get(observation_id, {}))
		if str(observation.get("state", "")) != "COMMITTED":
			continue
		var contributed := false
		for tag_value in _array(observation.get("hazard_tags", [])):
			var tag_id := str(tag_value)
			if tag_id.is_empty():
				continue
			contributed = true
			if not phenomenon_ids.has(tag_id):
				phenomenon_ids.append(tag_id)
		if contributed:
			sources.append({
				"source_kind": "OBSERVATION",
				"source_id": observation_id,
				"source_revision": int(observation.get("committed_tick", 0)),
				"contribution_kind": "SIGNAL"
			})

	# Older saves can contain the aggregate without the originating observation.
	# Keep it visible, but mark the provenance as a legacy aggregate rather than
	# inventing an observation source.
	for tag_value in _array(lot_state.get("known_hazard_tags", [])):
		var tag_id := str(tag_value)
		if not tag_id.is_empty() and not phenomenon_ids.has(tag_id):
			phenomenon_ids.append(tag_id)
	if not phenomenon_ids.is_empty() and sources.is_empty():
		sources.append({
			"source_kind": "LOT_STATE",
			"source_id": str(lot_state.get("lot_id", "")),
			"source_revision": current_tick,
			"contribution_kind": "SIGNAL"
		})

	phenomenon_ids.sort()
	return {
		"assessment_state": "SIGNAL_DETECTED" if not phenomenon_ids.is_empty() else "UNASSESSED",
		"qualifier_id": "",
		"severity_id": "",
		"phenomenon_ids": phenomenon_ids,
		"scopes": [],
		"sources": sources,
		"disclosure_state": "UNASSESSED",
		"projector_version": PROJECTOR_VERSION,
		"generated_at_tick": current_tick
	}


func _array(value) -> Array:
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []


func _dictionary(value) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}
