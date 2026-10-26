extends Control
class_name StyleUI
## Displays the Style singleton: feed lines, meter, rank letter, brink warning, beat pulse.

@export var meter: StyleMeterBar
@export var feed: StyleFeed
@export var rank_display: RankDisplay
@export var pulse_targets: Array[Control] = []   # nodes that pulse/tilt to the beat

@export_group("Pulse")
@export var pulse_scale := 0.06
@export var pulse_sharpness := 4.0
@export var tilt_degrees := 3.0
@export var hue_shift := 0.06

var _base := {}                          # pulse target -> [rotation, scale]


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	Style.award.connect(_on_award)
	Style.rank_changed.connect(_on_rank_changed)
	for t in pulse_targets:
		_base[t] = [t.rotation, t.scale]
	var r : Dictionary = Style.current_rank()
	rank_display.set_rank_instant(r["name"], r["color"], r["title"])
	meter.set_fill_color(r["color"])
	meter.set_value_instant(Style.progress())


func _on_award(text: String, pts: float, color: Color, key: StringName) -> void:
	feed.add_entry(text, color, key, "- " if pts < 0.0 else "+ ")


func _on_rank_changed(new_rank: int, _old_rank: int, up: bool) -> void:
	var r: Dictionary = Style.RANKS[new_rank]
	var intensity := float(new_rank) / float(Style.RANKS.size() - 1)
	rank_display.set_rank(r["name"], r["color"], r["title"], intensity, up)
	meter.set_fill_color(r["color"])
	meter.set_value_instant(Style.progress())


func _process(_delta: float) -> void:
	meter.value = Style.progress()
	meter.set_warning(Style.warning)
	rank_display.set_warning(Style.warning)
	_pulse()


func _pulse() -> void:
	var r : Dictionary = Style.current_rank()
	var env := 0.0
	var tilt := 0.0
	if Conductor.playing and not Conductor.stream_paused and Conductor.song_beat >= 0.0:
		var b := Conductor.song_beat
		var beat_env := pow(1.0 - fposmod(b, 1.0), pulse_sharpness)
		var in_bar := fposmod(b, float(Conductor.beats_per_bar))
		var down_env := pow(maxf(1.0 - in_bar, 0.0), pulse_sharpness)
		var eighth := b * 2.0
		var off_env := pow(1.0 - fposmod(eighth, 1.0), pulse_sharpness) if posmod(floori(eighth), 2) == 1 else 0.0
		env = maxf(maxf(r["beat"] * beat_env, r["down"] * down_env), r["off"] * off_env)
		if r["tilt"]:
			var side := 1.0 if posmod(floori(b), 2) == 0 else -1.0
			tilt = deg_to_rad(tilt_degrees) * beat_env * side
		if r["shift"]:
			var c: Color = r["color"]
			var shifted := Color.from_hsv(fposmod(c.h + sin(b * PI * 0.5) * hue_shift, 1.0), c.s, c.v)
			meter.set_fill_color(shifted)
			rank_display.set_color(shifted)

	for t in pulse_targets:
		var base: Array = _base[t]
		t.pivot_offset = t.size * 0.5
		t.scale = base[1] * (1.0 + pulse_scale * env)
		t.rotation = base[0] + tilt
