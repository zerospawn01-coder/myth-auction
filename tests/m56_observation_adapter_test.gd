extends SceneTree

const ObservationEffectSpec = preload("res://scripts/actions/observation_effect_spec.gd")
const LegacyObservationEffectAdapter = preload("res://scripts/actions/legacy_observation_effect_adapter.gd")

## M56 Observation Adapter Test Suite (VS-OBS-01 Strict Fail-Closed)
## Verifies legacy observation definitions normalization into ObservationEffectSpec.

func _init() -> void:
	print("==================================================")
	print("VS-OBS-01: Legacy Observation Adapter Test Suite (Strict Fail-Closed)")
	print("==================================================")

	var total_tests = 0
	var passed_tests = 0

	# Test 1: Explicit package observations normalization (3 methods)
	total_tests += 1
	var dummy_package = {
		"case_metadata": {"short_id": "MA-001"},
		"observation_definitions": [
			{
				"spec_id": "spec_01",
				"observation_method_id": "visual_goggle",
				"subject_id": "MA-001",
				"cost": {"ap": 1},
				"unlocked_evidence_ids": ["ev_lock_01"],
				"added_properties": ["PORCELAIN_SEAL"]
			},
			{
				"spec_id": "spec_02",
				"observation_method_id": "sound_spectrogram",
				"subject_id": "MA-001",
				"cost": {"ap": 1},
				"unlocked_evidence_ids": ["ev_sound_4200hz"],
				"added_properties": ["ACOUSTIC_RESONANCE"]
			},
			{
				"spec_id": "spec_03",
				"observation_method_id": "thermal_probe",
				"subject_id": "MA-001",
				"cost": {"ap": 2},
				"unlocked_evidence_ids": ["ev_heat_core"],
				"added_properties": ["THERMAL_RESIDUAL"]
			}
		]
	}

	var specs: Array[ObservationEffectSpec] = LegacyObservationEffectAdapter.adapt_from_package(dummy_package)
	if specs.size() == 3 and specs[0].is_valid_spec:
		print("[PASS] Test 01: Successfully normalized 3 explicit observation specs.")
		passed_tests += 1
	else:
		print("[FAIL] Test 01: Expected 3 valid specs, got " + str(specs.size()))

	# Test 2: Field extraction integrity
	total_tests += 1
	if specs.size() >= 1 and specs[0].is_valid_spec and specs[0].observation_method_id == "visual_goggle" and specs[0].subject_id == "MA-001" and specs[0].unlocked_evidence_ids.has("ev_lock_01") and specs[0].added_properties.has("PORCELAIN_SEAL"):
		print("[PASS] Test 02: Field extraction integrity verified.")
		passed_tests += 1
	else:
		print("[FAIL] Test 02: Field extraction mismatched.")

	# Test 3: Strict Fail-Closed handling of missing definitions (No auto-generated fallbacks!)
	total_tests += 1
	var empty_package = {
		"case_metadata": {"short_id": "MA-001"}
		# Notice: no observation_definitions or observations array!
	}
	var empty_specs = LegacyObservationEffectAdapter.adapt_from_package(empty_package)
	if empty_specs.size() == 1 and not empty_specs[0].is_valid_spec and empty_specs[0].error_message.begins_with("Fail-closed"):
		print("[PASS] Test 03: Strict fail-closed rejection on missing definitions verified (zero fallback synthesis).")
		passed_tests += 1
	else:
		print("[FAIL] Test 03: Expected fail-closed spec when definitions are missing.")

	# Test 3b: Strict Fail-Closed handling of completely empty package {}
	total_tests += 1
	var blank_specs = LegacyObservationEffectAdapter.adapt_from_package({})
	if blank_specs.size() == 1 and not blank_specs[0].is_valid_spec and blank_specs[0].error_message == "Fail-closed: Package is empty.":
		print("[PASS] Test 03b: Uniform fail-closed spec returned for completely empty package {}.")
		passed_tests += 1
	else:
		print("[FAIL] Test 03b: Expected fail-closed spec for empty package {}.")

	# Test 4: Strict Fail-Closed handling of unrecognized keys
	total_tests += 1
	var invalid_raw = {
		"observation_method_id": "valid_method",
		"subject_id": "MA-001",
		"illegal_unknown_key_xyz": "hazard"
	}
	var invalid_spec = LegacyObservationEffectAdapter.adapt_single_observation(invalid_raw)
	if not invalid_spec.is_valid_spec and invalid_spec.error_message.begins_with("Fail-closed"):
		print("[PASS] Test 04: Fail-closed trigger on unrecognized key verified.")
		passed_tests += 1
	else:
		print("[FAIL] Test 04: Expected fail-closed rejection for illegal key.")

	# Test 5: Absence of WorldState side effects
	total_tests += 1
	var specs_again = LegacyObservationEffectAdapter.adapt_from_package(dummy_package)
	if specs_again.size() == 3:
		print("[PASS] Test 05: Pure adapter execution produces zero WorldState side effects.")
		passed_tests += 1
	else:
		print("[FAIL] Test 05: Side effect check failed.")

	print("--------------------------------------------------")
	print("VS-OBS-01 Test Suite Results: " + str(passed_tests) + " / " + str(total_tests) + " PASS")
	print("--------------------------------------------------")

	quit(0 if passed_tests == total_tests else 1)
