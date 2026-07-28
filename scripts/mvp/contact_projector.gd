class_name ContactProjector
extends RefCounted

## Pure-function projector that derives runtime EmblemPresentation from contractor identity and relationship state.
## Risk and Trust are completely separate dimensions. Does NOT modify state or parse UI strings.

static func project(contractor: Dictionary, relationship: Dictionary, rules: Dictionary = {}) -> Dictionary:
	var contractor_id := str(contractor.get("id", "unknown_contractor"))
	var category := str(contractor.get("category", "researcher"))
	var relationship_id := str(contractor.get("relationship_id", ""))
	var emblem: Dictionary = contractor.get("emblem", {})
	
	# Fail-closed defaults for emblem definition
	var base_shape_id := str(emblem.get("base_shape_id", "shape_generic"))
	var primary_symbol_id := str(emblem.get("primary_symbol_id", "symbol_generic"))
	var palette_id := str(emblem.get("palette_id", "palette_neutral"))
	var org_mark_id := str(emblem.get("organization_mark_id", "mark_generic"))
	
	# Structural Risk is separate from Relationship Posture
	var risk_tier := str(emblem.get("risk_tier", "unknown"))
	
	# Extract canonical relationship state
	var trust: int = int(relationship.get("trust", 0))
	var obligation: int = int(relationship.get("obligation", 0))
	var status := str(relationship.get("status", "uncontacted"))
	
	# Format Asset IDs cleanly adhering to single-prefix rules
	var base_asset_id := _format_asset_id("base", base_shape_id, "emblem_base_shape_generic")
	var symbol_asset_id := _format_asset_id("symbol", primary_symbol_id, "emblem_symbol_generic")
	var mark_asset_id := _format_asset_id("mark", org_mark_id, "emblem_mark_generic")
	var formatted_palette_id := palette_id if not palette_id.is_empty() else "palette_neutral"
	
	# Extract thresholds from rules with fallback defaults
	var trust_gold_rim_threshold := int(rules.get("trust_gold_rim_threshold", 3))
	var trust_crack_threshold := int(rules.get("trust_crack_threshold", -2))
	var trust_thorn_threshold := int(rules.get("trust_thorn_threshold", -3))
	var obligation_seal_threshold := int(rules.get("obligation_seal_threshold", 3))
	var obligation_double_ring_threshold := int(rules.get("obligation_double_ring_threshold", 5))
	
	var overlays: Array[String] = []
	
	# 1. Status Overlays
	if status == "severed":
		overlays.append("overlay_sever_mark")
	elif status == "monitored" or trust < 0:
		overlays.append("overlay_watch_mark")
		
	# 2. Trust Overlays
	if trust >= trust_gold_rim_threshold:
		overlays.append("overlay_gold_rim")
	elif trust <= trust_crack_threshold and status != "severed":
		overlays.append("overlay_crack")
		
	if trust <= trust_thorn_threshold:
		overlays.append("overlay_thorn")
		
	# 3. Obligation Overlays
	if obligation >= obligation_seal_threshold:
		overlays.append("overlay_seal")
	if obligation >= obligation_double_ring_threshold:
		overlays.append("overlay_double_ring")
		
	return {
		"contractor_id": contractor_id,
		"relationship_id": relationship_id,
		"category": category,
		"base_asset_id": base_asset_id,
		"palette_id": formatted_palette_id,
		"symbol_asset_id": symbol_asset_id,
		"mark_asset_id": mark_asset_id,
		"overlays": overlays,
		"risk_tier": risk_tier
	}

static func _format_asset_id(category: String, id_value: String, fallback: String) -> String:
	if id_value.is_empty():
		return fallback
	if id_value.begins_with("emblem_"):
		return id_value
	if category == "base":
		if id_value.begins_with("base_"):
			return "emblem_" + id_value
		return "emblem_base_" + id_value
	elif category == "symbol":
		if id_value.begins_with("symbol_"):
			return "emblem_" + id_value
		return "emblem_symbol_" + id_value
	elif category == "mark":
		if id_value.begins_with("mark_"):
			return "emblem_" + id_value
		return "emblem_mark_" + id_value
	return "emblem_%s_%s" % [category, id_value]
