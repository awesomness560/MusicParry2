class_name AttackResult
extends RefCounted

enum Outcome { PERFECT_PARRY, PARRY, HIT }

var outcome := Outcome.HIT
var request: AttackRequest
var offset := 0.0                        # seconds, press - impact (negative = early). Parries only.
var group: Array[AttackRequest] = []     # every attack that landed on this beat, including this one


func is_parry() -> bool:
	return outcome != Outcome.HIT


func outcome_name() -> String:
	return Outcome.keys()[outcome]
