class_name AttackRequest
extends RefCounted
## Handle shared by the enemy, the scheduler, the resolver and the UI for one attack.

enum State { PENDING, BOOKED, WINDING_UP, DONE, CANCELLED }

signal booked(impact_beat: int)
signal started(lateness: float)      # begin windup now (lateness = seconds this frame was late)
signal impact(lateness: float)       # the hit lands now, on the beat
signal cancelled(reason: String)

# --- set by the enemy before requesting ---
var attacker: Node
var track_target: Node3D             # what the indicator follows; can be changed mid-attack
var attack_kind: StringName = &"melee"   # e.g. &"melee", &"projectile", &"laser"
var lead_time := 0.5                 # seconds from windup start to impact
var priority := 0.0
var slot_cost := 1
var beat_filter: Callable            # optional func(beat: int) -> bool
var max_wait_beats := 8

# --- filled by the scheduler ---
var state := State.PENDING
var requested_beat := 0
var impact_beat := -1
var start_time := 0.0
var impact_time := 0.0


func is_live() -> bool:
	return state == State.PENDING or state == State.BOOKED or state == State.WINDING_UP


func progress(now: float) -> float:
	return clampf((now - start_time) / maxf(impact_time - start_time, 0.0001), 0.0, 1.0)
