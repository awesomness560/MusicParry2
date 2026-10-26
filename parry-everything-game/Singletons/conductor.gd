extends AudioStreamPlayer
# Autoload as "Conductor" (a scene with this script on an AudioStreamPlayer, song set as its stream).
# Everything timing-related in the game reads song_time / beats from here.

signal beat(index: int)                 # every beat crossed, never skipped even on a lag spike
signal bar(index: int)                  # first beat of each bar
signal looped(loop_count: int)          # the stream wrapped around (looping imports only)
signal time_jumped(new_time: float)     # seek/restart: anything scheduled should re-plan
signal song_finished

@export var bpm: float = 126.0
@export var beats_per_bar: int = 4
@export var first_beat_offset: float = 0.0        # seconds into the file where beat 0 lands
@export var calibration_offset_ms: float = 0.0    # player-tunable; positive = game events happen later

## Seconds on the beat timeline. Continues across loops, frozen while paused.
var song_time := 0.0
## Fractional beat number (e.g. 12.5 = halfway between beats 12 and 13).
var song_beat := 0.0
## Last whole beat that has been emitted.
var beat_index := -1
## 0 -> 1 progress through the current beat, handy for pulsing visuals.
var beat_phase := 0.0

var _output_latency := 0.0
var _loop_count := 0
var _last_raw := 0.0
var _was_playing := false


func _ready() -> void:
	process_priority = -1000          # run before the scheduler, indicators and enemies
	_output_latency = AudioServer.get_output_latency()   # can be slow on some platforms, so cache it
	finished.connect(_on_finished)
	start()
	#seek_to(15)


# ---------------------------------------------------------------- control

func start(from_seconds := 0.0) -> void:
	play(from_seconds)
	_reset_timing(from_seconds)


func pause_song() -> void:
	stream_paused = true


func resume_song() -> void:
	stream_paused = false


func seek_to(seconds: float) -> void:
	seek(seconds)
	_reset_timing(seconds)
	time_jumped.emit(song_time)


# ---------------------------------------------------------------- conversions

func seconds_per_beat() -> float:
	return 60.0 / bpm


func beat_to_time(b: float) -> float:
	return first_beat_offset + b * seconds_per_beat()


func time_to_beat(t: float) -> float:
	return (t - first_beat_offset) / seconds_per_beat()


func time_until_beat(b: float) -> float:
	return beat_to_time(b) - song_time

## Song time computed right now rather than at the start of the frame. Use for timestamping input.
func precise_time() -> float:
	if not playing or stream_paused:
		return song_time
	var raw := get_playback_position() + AudioServer.get_time_since_last_mix() * pitch_scale
	var length := stream.get_length() if stream else 0.0
	var loops := _loop_count
	if length > 0.0 and raw < _last_raw - length * 0.5:
		loops += 1
	var t := raw + loops * length - _output_latency * pitch_scale - calibration_offset_ms / 1000.0
	return maxf(song_time, t)

# ---------------------------------------------------------------- per frame

func _process(_delta: float) -> void:
	var is_playing := playing and not stream_paused

	# catches play() called directly or autoplay, not just start()
	if playing and not _was_playing:
		_reset_timing(get_playback_position())
	_was_playing = playing

	if not is_playing:
		return    # paused or stopped: song_time freezes, so nothing in the game advances

	# playback position only updates once per mixed audio chunk; add the time since that mix
	var raw := get_playback_position() + AudioServer.get_time_since_last_mix() * pitch_scale

	# detect the stream wrapping around so the timeline keeps counting up
	var length := stream.get_length() if stream else 0.0
	if length > 0.0 and raw < _last_raw - length * 0.5:
		_loop_count += 1
		looped.emit(_loop_count)
	_last_raw = raw

	var t := raw + _loop_count * length
	t -= _output_latency * pitch_scale          # match what the player actually hears
	t -= calibration_offset_ms / 1000.0
	song_time = maxf(song_time, t)              # the raw value jitters backwards slightly

	song_beat = time_to_beat(song_time)
	var b := floori(song_beat)
	beat_phase = song_beat - b
	while beat_index < b:
		beat_index += 1
		beat.emit(beat_index)
		if beat_index >= 0 and beat_index % beats_per_bar == 0:
			bar.emit(beat_index / beats_per_bar)


# ---------------------------------------------------------------- internals

func _reset_timing(file_position: float) -> void:
	_loop_count = 0
	_last_raw = file_position
	_output_latency = AudioServer.get_output_latency()
	song_time = file_position - _output_latency * pitch_scale - calibration_offset_ms / 1000.0
	song_beat = time_to_beat(song_time)
	beat_index = floori(song_beat)              # don't re-emit beats we jumped past
	beat_phase = song_beat - beat_index
	_was_playing = playing


func _on_finished() -> void:
	_was_playing = false
	song_finished.emit()
