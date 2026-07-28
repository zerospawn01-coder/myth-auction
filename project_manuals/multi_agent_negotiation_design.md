# Aether Fountain: Multi-Agent Negotiation Gate Design

This document turns the current multi-agent negotiation concept into an implementation contract for Godot.

## 1. Dynamic Gate Arbitration

The gate must not rely on static ON/OFF priority flags. When multiple agents submit proposals in the same turn, the gate calculates a dynamic importance score from proposal data and ledger state.

Score inputs:

- `base_priority`
- `severity`
- `confidence`
- collapse timer urgency
- scenario progress
- proposal `timer_sensitivity`
- proposal `scenario_relevance`
- ledger conflict flags
- action cost
- cooldown penalty

If the top proposals are within `tie_threshold`, the gate returns `status = "escalated"` instead of guessing. This creates an explicit hold state where the player or a higher prompt can act as the auditor.

## 2. CastManager As Indirect Trigger

CastManager remains an observer and cannot directly rewrite card state.

Allowed behavior:

- flag contradictions
- request repair
- request coverup
- inject temporary priority variables into other agents' next turn

Forbidden behavior:

- direct card mutation
- bypassing the gate

Approved CastManager proposals produce `trigger_injections`, such as:

- `Director.priority_coverup += 20`
- `Engineer.priority_repair += 25`

This keeps agent independence intact. Agents do not talk to each other directly; they react to world-state and prompt-variable changes mediated by the gate.

## 3. Narrative Output

Raw arbitration data should be translated before it reaches the player. The audit console should present negotiation events as intercepted terminal records, not as debug traces.

Examples:

- `傍受された通信記録: データ干渉が発生中。監査官裁定を要求。`
- `傍受された通信記録: CastManager警告を受理。優先度注入を実行。`

Escalation states should become player intervention points. The user is treated as the highest-ranking auditor and can approve, reject, or defer the unresolved proposal.

## Runtime Files

- `res://scripts/agent_negotiation_gate.gd`
- `res://data/negotiation_rules.json`
- `res://tests/m04_negotiation_gate_test.gd`

## Minimal Proposal Shape

```json
{
  "id": "proposal_id",
  "agent_id": "Director",
  "role": "Director",
  "action_type": "advance_scene",
  "target": "card_001",
  "base_priority": 10,
  "severity": 20,
  "confidence": 0.8,
  "timer_sensitivity": 0.7,
  "scenario_relevance": 0.4,
  "cost": 2,
  "cooldown_key": "advance_scene:card_001"
}
```

## Gate Result Shape

```json
{
  "status": "approved",
  "winner": {},
  "scores": {},
  "trigger_injections": [],
  "reason": "highest_weight",
  "narrative_log": "..."
}
```
