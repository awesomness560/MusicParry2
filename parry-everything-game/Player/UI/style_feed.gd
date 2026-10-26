extends Control
class_name StyleFeed
## "+ Perfect parry" style lines. Newest at the top, older ones pushed down and stepped back,
## right-aligned to the slanted left edge of the style meter bar. Controlled with add_entry().

@export var bar: Control                  # the rotated StyleMeterBar the lines hug
@export var bar_inset := 10.0             # px from the bar node's edge to the visible bar (the shader margin)
@export var gap := 12.0                   # px between the text and the bar edge

@export_group("Text")
@export var font: Font
@export var font_size := 22
@export var outline_size := 6
@export var outline_color := Color(0, 0, 0, 0.85)

@export_group("Stack")
@export var max_lines := 6
@export var line_spacing := 26.0          # px between lines normally
@export var burst_spacing := 17.0         # px between lines during a flurry
@export var older_scale := 0.75           # scale of the bottom slot
@export var older_alpha := 0.4            # opacity of the bottom slot
@export var move_speed := 18.0            # how snappily lines slide to new slots

@export_group("Timing")
@export var lifetime := 2.5               # seconds before a line fades by itself
@export var fade_time := 0.35
@export var stack_repeats := true         # off = every entry gets its own new line
@export var merge_window := 1.5           # same entry within this time stacks as "×2", "×3"...

class Entry:
	var label: Label
	var key: StringName
	var base_text := ""
	var prefix := "+ "
	var count := 1
	var age := 0.0
	var pop := 1.0
	var fade := 0.0
	var leaving := false
	var y := 0.0

var _entries: Array[Entry] = []           # index 0 = newest
var _burst := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE

func add_entry(text: String, color := Color.WHITE, key: StringName = &"", prefix := "+ ") -> void:
	if key == &"":
		key = StringName(text)

	# same thing again shortly after: stack it on the newest line
	if stack_repeats and not _entries.is_empty():
		var top := _entries[0]
		if top.key == key and not top.leaving and top.age < merge_window:
			top.count += 1
			top.age = 0.0
			top.pop = 1.0
			top.label.text = "%s%s ×%d" % [top.prefix, top.base_text, top.count]
			_burst += 0.5
			return

	var e := Entry.new()
	e.key = key
	e.base_text = text
	e.prefix = prefix
	e.label = Label.new()
	e.label.text = prefix + text
	e.label.mouse_filter = MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	if font:
		ls.font = font
	ls.font_size = font_size
	ls.font_color = color
	ls.outline_size = outline_size
	ls.outline_color = outline_color
	e.label.label_settings = ls
	add_child(e.label)
	e.y = -line_spacing * 0.7             # drop in from just above the top slot
	_entries.insert(0, e)
	_burst += 1.0

	# over the limit: the oldest get pushed out
	for i in range(max_lines, _entries.size()):
		_entries[i].leaving = true

func clear() -> void:
	for e in _entries:
		e.leaving = true


func _process(delta: float) -> void:
	_burst = maxf(_burst - delta * 2.5, 0.0)
	var spacing := lerpf(line_spacing, burst_spacing, clampf(_burst / 3.0, 0.0, 1.0))
	var k := 1.0 - exp(-move_speed * delta)

	for i in range(_entries.size() - 1, -1, -1):
		var e := _entries[i]
		e.age += delta
		e.pop = maxf(e.pop - delta * 5.0, 0.0)
		if e.age > lifetime:
			e.leaving = true
		if e.leaving:
			e.fade += delta / fade_time
			if e.fade >= 1.0:
				e.label.queue_free()
				_entries.remove_at(i)
				continue

		e.y = lerpf(e.y, i * spacing, k)

		# stepped back: lower slots are smaller and dimmer
		var depth := clampf(float(i) / maxf(max_lines - 1, 1), 0.0, 1.0)
		var s := lerpf(1.0, older_scale, depth) * (1.0 + 0.3 * e.pop * e.pop)
		var a := lerpf(1.0, older_alpha, depth) * (1.0 - clampf(e.fade, 0.0, 1.0))

		# right-align to the slanted bar edge, scaling from the right so it stays tight
		var lsize := e.label.get_minimum_size()
		e.label.size = lsize
		e.label.pivot_offset = Vector2(lsize.x, lsize.y * 0.5)
		e.label.scale = Vector2(s, s)
		var right := _edge_x_at(e.y) - gap - 18.0 * e.pop * e.pop
		e.label.position = Vector2(right - lsize.x, e.y - lsize.y * 0.5)
		e.label.modulate.a = a


# x of the bar's left edge at a given y, in this node's local space
func _edge_x_at(local_y: float) -> float:
	if bar == null:
		return size.x
	var to_local := get_global_transform().affine_inverse() * bar.get_global_transform()
	var a := to_local * Vector2(bar_inset, 0.0)
	var b := to_local * Vector2(bar_inset, bar.size.y)
	if is_equal_approx(a.y, b.y):
		return a.x
	var t := (local_y - a.y) / (b.y - a.y)
	return lerpf(a.x, b.x, t)
