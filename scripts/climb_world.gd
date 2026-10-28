## Screw-motion world: everything under this node (tower, helix stairs, background wall,
## chains, props) is rotated around the tower axis and lowered so the fixed camera appears
## to climb the stairs. Because a helix is invariant under "rotate by θ, translate by
## θ·pitch/2π", the motion is seamless; after one full turn the node snaps back by exactly
## one pitch, which is invisible as long as every child repeats per turn.
class_name ClimbWorld
extends Node3D

## Seconds per full revolution (one turn of the stairs).
@export var seconds_per_turn := 9.0
## Height climbed per revolution (steps_per_turn * step_height).
@export var pitch := 14.4
## Height at which the step at angle 0 sits when phase = 0.
@export var base_y := 2.0
## 1 = climbing, 0 = frozen, -1 = descending.
@export var climb := 1.0
## Nodes that must only rotate (far parallax layers that have no vertical period).
@export var rotate_only: Array[Node3D] = []

## Stair layout, used by [method step_transform] to place enemies / pickups on a step.
@export var steps_per_turn := 36
@export var step_height := 0.4
@export var lane_radius := 6.5

var phase := 0.0   # 0..1 fraction of a revolution


## Local transform (relative to this node) of the centre of step [index]; the step at
## index 0 is the one in front of the camera at phase 0. Attach future enemies as children
## of this node with this transform and they ride the stairs toward the player.
func step_transform(index: int) -> Transform3D:
	var da := TAU / steps_per_turn
	var a := (index + 0.5) * da
	var pos := Vector3(lane_radius * sin(a), index * step_height, lane_radius * cos(a))
	return Transform3D(Basis(Vector3.UP, a), pos)


## Step index currently in front of the camera (fractional).
func current_step() -> float:
	return phase * steps_per_turn


func _process(delta: float) -> void:
	if seconds_per_turn > 0.0:
		phase += climb * delta / seconds_per_turn
		phase = fposmod(phase, 1.0)
	apply_phase()


func apply_phase() -> void:
	var ang := -phase * TAU
	rotation.y = ang
	position.y = base_y - phase * pitch
	for n in rotate_only:
		if is_instance_valid(n):
			n.rotation.y = ang
