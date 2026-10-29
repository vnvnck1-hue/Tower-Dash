## AI Director (Left 4 Dead style pacing) for the goblin spawns.
##
## One "intensity" value (0..1) tracks how stressed the runner is right now, L4D's per-survivor
## emotional intensity: it jumps when the runner is hit or falls, grows while enemies are close,
## ticks up a little per kill, and decays back toward zero once nothing has happened for a moment.
##
## The pacing runs L4D's cycle: BUILD_UP (spawns on, density = how LOW the intensity is) ->
## SUSTAIN_PEAK (a few seconds, no new spawns, the runner finishes what is already there) ->
## RELAX (sparse wanderers until the intensity has dropped under a threshold and a minimum
## rest has passed) -> BUILD_UP. A build-up that never reaches the peak on its own is ended
## with a forced surge, like L4D's forced mob after the maximum build-up time.
##
## Spawns land on a beat grid: the caller asks for one slot per beat and gets back how many
## goblins that beat carries (0, 1 or an accented 2). A bar is 4 beats; the pattern per bar is
## picked from the intensity, so a calm runner meets a goblin on every beat and a stressed one
## only on the downbeat.
class_name Director
extends RefCounted

enum { BUILD_UP, SUSTAIN_PEAK, RELAX }
const STATE_NAMES := ["build_up", "peak", "relax"]

# ---- intensity tuning ----
const HURT_INTENSITY := 0.45       # lost a heart (hit or fell into a gap)
const KILL_INTENSITY := 0.07       # per kill (a brawl keeps the intensity up on its own)
const THREAT_RATE := 0.16          # per second while an enemy is within striking range
const DECAY_RATE := 0.11           # per second once the grace is over (full -> 0 in ~9 s)
const DECAY_GRACE := 1.4           # seconds after the last event before the decay starts

# ---- pacing tuning (seconds; L4D uses 15 / 3..5 / 30..45, shortened for a runner) ----
const BUILD_UP_MIN := 6.0
const BUILD_UP_MAX := 26.0         # forced surge after this
const PEAK_THRESHOLD := 0.8        # intensity that ends the build-up
const PEAK_MIN := 3.0
const PEAK_MAX := 5.0
const RELAX_THRESHOLD := 0.3       # intensity the runner must be under before relax may end
const RELAX_MIN := 5.0
const RELAX_MAX := 12.0

# ---- rhythm ----
const BEAT_SECONDS := 0.9          # one spawn slot every 0.9 s of climbing (~67 BPM)
const BEATS_PER_BAR := 4
const MIN_BEAT_STEPS := 3.0        # never closer than this, whatever the climb speed
## Bar patterns by intensity band (low -> high): goblins per beat, 2 = accented pair.
const PATTERNS := [
	[2, 1, 1, 1],   # intensity < 0.25: calm runner, something on every beat
	[1, 1, 0, 1],   # < 0.5
	[1, 0, 1, 0],   # < 0.75
	[1, 0, 0, 0],   # >= 0.75: only the downbeat
]
const SURGE_PATTERN := [2, 2, 1, 2]
const RELAX_PATTERN := [1, 0, 0, 0]

var intensity := 0.0
var state := BUILD_UP
var state_t := 0.0                # seconds in the current state
var beat := 0                     # 0..BEATS_PER_BAR-1, the next slot handed out
var bars := 0                     # bars handed out so far (debug / variation)
var surge_bars := 0               # bars of SURGE_PATTERN still owed
var _quiet_t := 0.0               # seconds since the last intensity event
var _peak_len := 4.0
var _rng := RandomNumberGenerator.new()


func _init(seed_: int = 7) -> void:
	_rng.seed = seed_
	_peak_len = _rng.randf_range(PEAK_MIN, PEAK_MAX)


## Lost a heart: the biggest single intensity hit.
func on_hurt() -> void:
	_bump(HURT_INTENSITY)


## Killed a goblin. [multi] = part of a 3+ multi-kill (slightly more, the runner is in a brawl).
func on_kill(multi := false) -> void:
	_bump(KILL_INTENSITY * (1.6 if multi else 1.0))


func _bump(v: float) -> void:
	intensity = clamp(intensity + v, 0.0, 1.0)
	_quiet_t = 0.0


## Per frame (game delta). [threat] = an enemy is within striking range or an arrow is close.
func tick(delta: float, threat: bool) -> void:
	if threat:
		intensity = clamp(intensity + THREAT_RATE * delta, 0.0, 1.0)
		_quiet_t = 0.0
	else:
		_quiet_t += delta
		if _quiet_t >= DECAY_GRACE:
			intensity = max(intensity - DECAY_RATE * delta, 0.0)
	state_t += delta
	match state:
		BUILD_UP:
			if state_t >= BUILD_UP_MIN and intensity >= PEAK_THRESHOLD:
				_enter(SUSTAIN_PEAK)
			elif state_t >= BUILD_UP_MAX:
				# never got stressed: owe one surge bar, then peak regardless (L4D forced mob)
				surge_bars = 1
				_enter(SUSTAIN_PEAK)
		SUSTAIN_PEAK:
			if state_t >= _peak_len:
				_enter(RELAX)
		RELAX:
			if (state_t >= RELAX_MIN and intensity < RELAX_THRESHOLD) or state_t >= RELAX_MAX:
				_enter(BUILD_UP)


func _enter(s: int) -> void:
	state = s
	state_t = 0.0
	if s == SUSTAIN_PEAK:
		_peak_len = _rng.randf_range(PEAK_MIN, PEAK_MAX)
	elif s == BUILD_UP:
		beat = 0   # a new bar starts the build-up so the downbeat lands first


## Beat spacing in steps for the current climb rate (steps per second).
func beat_steps(climb_rate: float) -> float:
	return max(BEAT_SECONDS * climb_rate, MIN_BEAT_STEPS)


## Hands out the next beat slot: how many goblins to put on it (0 / 1 / 2 = accented pair).
func next_beat() -> int:
	var pattern: Array
	if surge_bars > 0:
		pattern = SURGE_PATTERN
	else:
		match state:
			BUILD_UP:
				pattern = PATTERNS[_band()]
			SUSTAIN_PEAK:
				pattern = [0, 0, 0, 0]
			_:
				# relax: a lone wanderer on about half the downbeats
				pattern = RELAX_PATTERN if (bars % 2 == 0) else [0, 0, 0, 0]
	var n: int = pattern[beat]
	beat += 1
	if beat >= BEATS_PER_BAR:
		beat = 0
		bars += 1
		if surge_bars > 0:
			surge_bars -= 1
	return n


## True on the last beat of a bar: the caller may make this one an archer.
func is_bar_end() -> bool:
	return beat == BEATS_PER_BAR - 1


func _band() -> int:
	if intensity < 0.25:
		return 0
	if intensity < 0.5:
		return 1
	if intensity < 0.75:
		return 2
	return 3


func debug_text() -> String:
	return "%s %.1fs  I=%.2f  bar %d beat %d%s" % [STATE_NAMES[state], state_t, intensity, bars, beat + 1, "  SURGE" if surge_bars > 0 else ""]
