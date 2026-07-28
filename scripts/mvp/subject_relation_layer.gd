## M57 — SubjectRelationLayer utility.
##
## Static helpers for building and classifying M57 domain records.
## No live state mutations — returns plain Dictionaries that the
## EffectApplier and EffectContractRegistry use as data-only plans.

extends RefCounted
class_name SubjectRelationLayer

const RELATION_STATES    := ["NEW", "ACTIVE", "DORMANT", "CLOSED", "LOST", "TRANSFERRED"]
const MATURITY_FLAGS     := ["UNOBSERVED", "OBSERVED", "CHARACTERIZED", "HYPOTHESIZED",
                              "TESTED", "REPLICATED", "CONTESTED", "PUBLISHED"]
const LINK_TYPES         := ["REVISITS", "REPLICATES", "COMPARES_WITH",
                              "CONTRADICTS", "REINTERPRETS", "EXTENDS"]
const REPLICATION_TYPES  := ["REPLICATION", "COMPARISON", "DISCOVERY"]


# ── Builders ──────────────────────────────────────────────────────────────────

## Initial SubjectRelation record created when a lot is received.
static func build_subject_relation(subject_id: String, tick: int, event_id: String) -> Dictionary:
	return {
		"subject_id":                  subject_id,
		"relation_state":              "NEW",
		"first_contact_tick":          tick,
		"first_contact_record_id":     event_id,
		"last_action_tick":            tick,
		"last_action_record_id":       event_id,
		"active_research_thread_ids":  [],
		"maturity_flags":              [],
		"closed_reason":               ""
	}


## ResearchThread record keyed by a normalised inquiry_key.
static func build_research_thread(
	subject_ids: Array,
	inquiry_key: String,
	tick: int,
	event_id: String
) -> Dictionary:
	var thread_id := "THR-%s" % _short_hash(inquiry_key + str(tick))
	return {
		"thread_id":                           thread_id,
		"subject_ids":                         subject_ids.duplicate(),
		"inquiry_key":                         inquiry_key,
		"hypothesis_ids":                      [],
		"evidence_ids":                        [],
		"claim_ids":                           [],
		"status":                              "OPEN",
		"opened_by_action_record_id":          event_id,
		"last_updated_by_action_record_id":    event_id,
		"opened_tick":                         tick
	}


## Directed provenance link between two ledger event IDs.
static func build_action_record_link(
	source_id: String,
	target_id: String,
	link_type: String,
	tick: int
) -> Dictionary:
	return {
		"source_action_record_id": source_id,
		"target_action_record_id": target_id,
		"link_type":               link_type,
		"created_tick":            tick
	}


## Canonical key used to detect duplicate research threads.
## All parts are lowercased and stripped so that trivial variations collapse.
static func build_inquiry_key(subject_id: String, action_type: String, dimension: String) -> String:
	return "%s::%s::%s" % [
		subject_id.strip_edges(),
		action_type.to_lower().strip_edges(),
		dimension.to_lower().strip_edges()
	]


# ── Classifiers ───────────────────────────────────────────────────────────────

## Determine the replication class when revisiting a past observation.
##
## Parameters:
##   source_maturity_flags — maturity_flags recorded on SubjectRelation AT THE TIME
##                           the source observation was committed (snapshotted in record).
##   current_maturity_flags — maturity_flags NOW on the live SubjectRelation.
##
## Returns one of: "REPLICATION" / "COMPARISON" / "DISCOVERY"
##
## Logic:
##   • Any flag present NOW that was absent then  → DISCOVERY  (new capability unlocked)
##   • Same flags, same count                     → REPLICATION (identical conditions)
##   • Count differs without new additions        → COMPARISON  (conditions narrowed)
static func classify_replication(
	source_maturity_flags: Array,
	current_maturity_flags: Array
) -> String:
	for flag in current_maturity_flags:
		if not source_maturity_flags.has(flag):
			return "DISCOVERY"
	if current_maturity_flags.size() == source_maturity_flags.size():
		return "REPLICATION"
	return "COMPARISON"


## What ResearchMaturity flag does a successful M57 action add?
static func maturity_flag_from_action(action_type: String) -> String:
	match action_type.to_upper():
		"REEXAMINE_SUBJECT":     return "CHARACTERIZED"
		"COMPARE_SUBJECTS":      return "HYPOTHESIZED"
		"REPLICATE_OBSERVATION": return "TESTED"
		"REINTERPRET_EVIDENCE":  return "CHARACTERIZED"
		_:                        return ""


# ── Lookup helpers ────────────────────────────────────────────────────────────

## True if any ResearchThread in the dict already uses this key.
static func has_inquiry_key(research_threads: Dictionary, key: String) -> bool:
	for thread_value in research_threads.values():
		if typeof(thread_value) == TYPE_DICTIONARY:
			if str((thread_value as Dictionary).get("inquiry_key", "")) == key:
				return true
	return false


## Find a thread by inquiry_key. Returns empty dict if not found.
static func get_thread_for_key(research_threads: Dictionary, key: String) -> Dictionary:
	for thread_value in research_threads.values():
		if typeof(thread_value) == TYPE_DICTIONARY:
			var t: Dictionary = thread_value
			if str(t.get("inquiry_key", "")) == key:
				return t.duplicate(true)
	return {}


# ── Internal ──────────────────────────────────────────────────────────────────

static func _short_hash(value: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(value.to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16).to_upper()

