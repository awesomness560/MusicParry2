extends Node
## Autoload as "AttackScheduler". Books attack impacts onto beats and cues attackers.

signal attack_booked(request: AttackRequest)
signal attack_started(request: AttackRequest)
signal attack_impact(request: AttackRequest)
signal attack_cancelled(request: AttackRequest)

const S = AttackRequest.State

@export var max_impacts_per_beat := 2
@export var rest_beats := 1                 # beats on each side of a booked beat that stay empty
@export var max_concurrent_windups := 3
@export var beat_every := 1                 # allowed pattern: 1 = every beat, 2 = every other...
@export var beat_offset := 0
@export var min_warning := 0.0              # seconds; floor on booking-to-impact time
@export var safety_margin := 0.03           # seconds; never book a start time that's basically now
@export var lookahead_beats := 32
@export var aging_per_beat := 0.25          # priority gained per beat of waiting

var _pending: Array[AttackRequest] = []
var _booked: Array[AttackRequest] = []      # BOOKED or WINDING_UP
var _slots := {}                            # beat index -> slots used (kept after impact for rest windows)


func _ready() -> void:
	process_priority = -900                 # after the Conductor (-1000), before enemies and UI (0)
	Conductor.time_jumped.connect(_on_time_jumped)


# ---------------------------------------------------------------- public API

func request(r: AttackRequest) -> AttackRequest:
	if r == null or r.is_live() and r.state != S.PENDING:
		return r
	r.state = S.PENDING
	r.requested_beat = floori(Conductor.song_beat)
	_pending.append(r)
	return r


func cancel(r: AttackRequest, reason := "cancelled") -> void:
	if r == null or not r.is_live():
		return
	if r.state == S.PENDING:
		_pending.erase(r)
	else:
		_booked.erase(r)
		_release_slot(r)                    # also removes the rest window it created
	r.state = S.CANCELLED
	r.cancelled.emit(reason)
	attack_cancelled.emit(r)


func cancel_all(reason := "cancelled") -> void:
	for r in _pending.duplicate():
		cancel(r, reason)
	for r in _booked.duplicate():
		cancel(r, reason)


# ---------------------------------------------------------------- per frame

func _process(_delta: float) -> void:
	if not Conductor.playing or Conductor.stream_paused:
		return
	var now := Conductor.song_time
	_book_pending(now)
	_advance(now)
	_prune_slots()


func _book_pending(now: float) -> void:
	if _pending.is_empty():
		return
	var cur := floori(Conductor.song_beat)
	_pending.sort_custom(func(a: AttackRequest, b: AttackRequest) -> bool:
		var pa := a.priority + aging_per_beat * (cur - a.requested_beat)
		var pb := b.priority + aging_per_beat * (cur - b.requested_beat)
		return pa > pb if not is_equal_approx(pa, pb) else a.requested_beat < b.requested_beat)

	for r in _pending.duplicate():
		if not is_instance_valid(r.attacker):
			cancel(r, "attacker_gone")
			continue
		if cur - r.requested_beat > r.max_wait_beats:
			cancel(r, "timeout")
			continue
		var b := _find_beat(r, now)
		if b == -1:
			continue
		_pending.erase(r)
		r.impact_beat = b
		r.impact_time = Conductor.beat_to_time(b)
		r.start_time = r.impact_time - r.lead_time
		r.state = S.BOOKED
		_slots[b] = _slots.get(b, 0) + r.slot_cost
		_booked.append(r)
		r.booked.emit(b)
		attack_booked.emit(r)


func _advance(now: float) -> void:
	for r in _booked.duplicate():
		if not is_instance_valid(r.attacker):
			cancel(r, "attacker_gone")
			continue
		if r.state == S.BOOKED and now >= r.start_time:
			r.state = S.WINDING_UP
			r.started.emit(now - r.start_time)
			attack_started.emit(r)
		# separate if: a lag spike can cross both start and impact in one frame
		if r.state == S.WINDING_UP and now >= r.impact_time:
			r.state = S.DONE
			_booked.erase(r)                # slot stays in _slots so the rest window holds
			r.impact.emit(now - r.impact_time)
			attack_impact.emit(r)


# ---------------------------------------------------------------- booking rules

func _find_beat(r: AttackRequest, now: float) -> int:
	var lead := maxf(r.lead_time, min_warning)
	var first := ceili(Conductor.time_to_beat(now + lead + safety_margin))
	var every := maxi(beat_every, 1)
	for b in range(first, first + lookahead_beats):
		if posmod(b - beat_offset, every) != 0:
			continue
		if r.beat_filter.is_valid() and not r.beat_filter.call(b):
			continue
		if _slots.get(b, 0) + r.slot_cost > max_impacts_per_beat:
			continue
		if _in_rest_window(b):
			continue
		var t := Conductor.beat_to_time(b)
		if _windups_overlapping(t - r.lead_time, t) >= max_concurrent_windups:
			continue
		return b
	return -1


func _in_rest_window(b: int) -> bool:
	for k in range(1, rest_beats + 1):
		if _slots.get(b - k, 0) > 0 or _slots.get(b + k, 0) > 0:
			return true
	return false


func _windups_overlapping(t0: float, t1: float) -> int:
	var n := 0
	for r in _booked:
		if r.start_time < t1 and r.impact_time > t0:
			n += 1
	return n


func _release_slot(r: AttackRequest) -> void:
	if r.impact_beat < 0:
		return
	var left: int = _slots.get(r.impact_beat, 0) - r.slot_cost
	if left > 0:
		_slots[r.impact_beat] = left
	else:
		_slots.erase(r.impact_beat)


func _prune_slots() -> void:
	# forget beats far enough in the past that they can't affect any rest window
	var oldest_needed := floori(Conductor.song_beat) - rest_beats - 1
	for b in _slots.keys():
		if b < oldest_needed:
			_slots.erase(b)


func _on_time_jumped(_new_time: float) -> void:
	cancel_all("time_jump")
	_slots.clear()
