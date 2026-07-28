extends SceneTree

const MythMvpStateScript = preload("res://scripts/mvp/myth_mvp_state.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting MA-001 Save Schema Migration Test (M46) ---")
	_test_save_and_determinism_versions_are_independent()
	_test_v2_package_identity_roundtrip()
	_test_legacy_v1_migrates_without_trace_mutation()
	_test_legacy_hash_is_checked_before_migration()
	_test_v2_package_identity_is_pinned()
	_finish()


func _test_save_and_determinism_versions_are_independent() -> void:
	var state = _new_researched_state()
	if state == null:
		return
	if MythMvpStateScript.SAVE_SCHEMA_VERSION != 2:
		_fail("M46-1: Save schema version must be 2.")
	var determinism_version := int(state.resolver.get_determinism_version())
	if determinism_version == MythMvpStateScript.SAVE_SCHEMA_VERSION:
		_fail("M46-1: MA-001 determinism version must not inherit save schema v2.")
	var observation: Dictionary = state.observations.get("OBS-MA001-VISUAL", {})
	var expected: Dictionary = state.resolver.resolve_observation("obs_visual", determinism_version)
	if str(observation.get("result_seed", "")) != str(expected.get("result_seed", "")):
		_fail("M46-1: Observation resolution did not use package determinism version.")
	var wrong_version: Dictionary = state.resolver.resolve_observation("obs_visual", MythMvpStateScript.SAVE_SCHEMA_VERSION)
	if str(expected.get("result_seed", "")) == str(wrong_version.get("result_seed", "")):
		_fail("M46-1: Characterization fixture cannot distinguish determinism v1 from save schema v2.")


func _test_v2_package_identity_roundtrip() -> void:
	var state = _new_researched_state()
	if state == null:
		return
	var snapshot: Dictionary = state.to_dictionary()
	if int(snapshot.get("schema_version", 0)) != 2:
		_fail("M46-2: New snapshots must use save schema v2.")
	var identity: Dictionary = snapshot.get("package_identity", {})
	for key in ["package_id", "package_version", "package_schema_version", "determinism_version", "package_content_hash"]:
		if not identity.has(key) or str(identity.get(key, "")).is_empty():
			_fail("M46-2: v2 package identity is missing %s." % key)
	var restored = MythMvpStateScript.new()
	if not restored.initialize() or not restored.load_from_dictionary(snapshot):
		_fail("M46-2: v2 snapshot did not roundtrip: %s" % restored.last_error)
		return
	if restored.trace_ledger.to_dictionary() != state.trace_ledger.to_dictionary():
		_fail("M46-2: v2 roundtrip changed TraceLedger entries or hash tip.")


func _test_legacy_v1_migrates_without_trace_mutation() -> void:
	var state = _new_researched_state()
	if state == null:
		return
	var legacy := _make_legacy_v1_snapshot(state.to_dictionary(), state)
	var legacy_before := legacy.duplicate(true)
	var trace_before: Dictionary = legacy.get("trace_ledger", {}).duplicate(true)
	var legacy_path := "user://m45_ma001_legacy_v1.json"
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	if file == null:
		_fail("M46-3: Could not write legacy save fixture.")
		return
	file.store_string(JSON.stringify(legacy, "  ", false))
	file = null
	var restored = MythMvpStateScript.new()
	if not restored.initialize() or not restored.load_from_file(legacy_path):
		_fail("M46-3: Valid legacy v1 save did not migrate: %s" % restored.last_error)
		return
	if legacy != legacy_before:
		_fail("M46-3: Migration mutated its source v1 Dictionary.")
	if restored.trace_ledger.to_dictionary() != trace_before:
		_fail("M46-3: Migration changed existing TraceLedger entries or appended an event.")
	if restored.tick != int(legacy.get("tick", -1)):
		_fail("M46-3: Migration changed the case tick.")
	var migrated: Dictionary = restored.to_dictionary()
	if int(migrated.get("schema_version", 0)) != 2:
		_fail("M46-3: Migrated state did not save back as v2.")
	if typeof(migrated.get("package_identity", null)) != TYPE_DICTIONARY:
		_fail("M46-3: Migrated v2 save lacks package identity.")
	var migrated_listing: Dictionary = migrated.get("listing", {})
	for key in ["restrictions", "sales_restrictions", "sales_restriction_ids"]:
		if not migrated_listing.has(key):
			_fail("M46-3: Legacy listing was not completed with %s." % key)
	for key in ["unlocked_followups", "last_search_tags", "last_search_result_ids", "next_commission_sequence"]:
		if not migrated.has(key):
			_fail("M46-3: Legacy snapshot was not completed with %s." % key)


func _test_legacy_hash_is_checked_before_migration() -> void:
	var source = _new_researched_state()
	if source == null:
		return
	var tampered := _make_legacy_v1_snapshot(source.to_dictionary(), source)
	tampered["claim"]["claim_text"] = "tampered before migration"
	var target = MythMvpStateScript.new()
	if not target.initialize() or not target.receive_lot():
		_fail("M46-4: Atomicity target setup failed.")
		return
	var tick_before: int = int(target.tick)
	var lot_before: Dictionary = target.lot_state.duplicate(true)
	if target.load_from_dictionary(tampered):
		_fail("M46-4: Tampered v1 save must be rejected before migration.")
	if target.tick != tick_before or target.lot_state != lot_before:
		_fail("M46-4: Failed legacy migration partially mutated live State.")


func _test_v2_package_identity_is_pinned() -> void:
	var source = _new_researched_state()
	if source == null:
		return
	var forged: Dictionary = source.to_dictionary().duplicate(true)
	forged["package_identity"]["package_version"] = "forged-version"
	forged = _rehash_snapshot(forged, source)
	var target = MythMvpStateScript.new()
	if not target.initialize():
		_fail("M46-5: Package identity target setup failed.")
		return
	if target.load_from_dictionary(forged):
		_fail("M46-5: Rehashed snapshot with a mismatched package identity must fail closed.")
	if target.tick != 0 or not target.trace_ledger.entries.is_empty():
		_fail("M46-5: Package identity rejection partially mutated State or TraceLedger.")


func _new_researched_state():
	var state = MythMvpStateScript.new()
	if not state.initialize():
		_fail("M46 setup: State initialization failed: %s" % state.last_error)
		return null
	if not state.receive_lot():
		_fail("M46 setup: Lot intake failed: %s" % state.last_error)
		return null
	if state.commit_observation("obs_visual").is_empty():
		_fail("M46 setup: Observation commit failed.")
		return null
	return state


func _make_legacy_v1_snapshot(v2_snapshot: Dictionary, state) -> Dictionary:
	var legacy := v2_snapshot.duplicate(true)
	legacy.erase("snapshot_hash")
	legacy.erase("package_identity")
	legacy["schema_version"] = 1
	# Exercise completion of fields introduced while schema 1 was still active.
	legacy.erase("unlocked_followups")
	legacy.erase("last_search_tags")
	legacy.erase("last_search_result_ids")
	legacy.erase("next_commission_sequence")
	legacy["listing"].erase("restrictions")
	legacy["listing"].erase("sales_restrictions")
	legacy["listing"].erase("sales_restriction_ids")
	return _rehash_snapshot(legacy, state)


func _rehash_snapshot(snapshot: Dictionary, state) -> Dictionary:
	var sealed := snapshot.duplicate(true)
	sealed.erase("snapshot_hash")
	var normalized = JSON.parse_string(JSON.stringify(sealed, "", true, false))
	sealed["snapshot_hash"] = state.trace_ledger.deterministic_hash(normalized)
	return sealed


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- MA-001 SAVE SCHEMA MIGRATION TEST PASSED ---")
		quit(0)
		return
	print("--- MA-001 SAVE SCHEMA MIGRATION TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
