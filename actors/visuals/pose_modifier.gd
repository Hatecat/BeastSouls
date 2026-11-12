class_name PoseModifier
extends SkeletonModifier3D
## Capa procedural sobre los clips: la cabeza sigue un punto (el rival fijado) y el torso se dobla al recibir
## un golpe. Las rotaciones se calculan en el espacio del CharacterVisual (adelante = -Z) y se pasan al del
## esqueleto, así que no dependen de cómo estén orientados los huesos de cada modelo.

var visual: Node3D
var head_bone := -1
var neck_bone := -1
var chest_bone := -1
## Punto del mundo al que mirar (Vector3.INF = al frente).
var look_point := Vector3.INF
var look_limit_yaw := deg_to_rad(55.0)
var look_limit_pitch := deg_to_rad(28.0)

var _yaw := 0.0
var _pitch := 0.0
## Flexión por golpe: vector de rotación (eje * ángulo) en el espacio del visual, con muelle.
var _flinch := Vector3.ZERO
var _flinch_vel := Vector3.ZERO


## `push_dir` (mundo): hacia dónde empuja el golpe. El torso se dobla en esa dirección y vuelve con rebote.
func flinch(push_dir: Vector3, strength: float) -> void:
	if visual == null:
		return
	var local := visual.global_basis.orthonormalized().inverse() * push_dir
	local.y = 0.0
	if local.length_squared() < 0.0001:
		local = Vector3(0, 0, 1)
	_flinch_vel += Vector3.UP.cross(local.normalized()) * strength * 14.0


func flinch_amount() -> Vector3:
	return _flinch


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or visual == null or not visual.is_inside_tree():
		return
	var v_basis := visual.global_basis.orthonormalized()
	var conv := skel.global_basis.orthonormalized().inverse() * v_basis
	# --- Mirada ---
	var want_yaw := 0.0
	var want_pitch := 0.0
	if head_bone >= 0 and look_point.is_finite():
		var head_world := skel.global_transform * skel.get_bone_global_pose(head_bone).origin
		var d := v_basis.inverse() * (look_point - head_world)
		if d.length() > 0.4:
			var yaw := atan2(d.x, -d.z)
			if absf(yaw) < deg_to_rad(115.0):
				want_yaw = clampf(yaw, -look_limit_yaw, look_limit_yaw)
				want_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -look_limit_pitch, look_limit_pitch)
	var k := 1.0 - exp(-7.0 * delta)
	_yaw = lerpf(_yaw, want_yaw, k)
	_pitch = lerpf(_pitch, want_pitch, k)
	if head_bone >= 0 and (absf(_yaw) > 0.003 or absf(_pitch) > 0.003):
		var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), -cos(_yaw) * cos(_pitch))
		var q := Quaternion(Vector3.FORWARD, dir)
		if neck_bone >= 0:
			_rotate(skel, neck_bone, conv, Basis(Quaternion.IDENTITY.slerp(q, 0.4)))
			_rotate(skel, head_bone, conv, Basis(Quaternion.IDENTITY.slerp(q, 0.6)))
		else:
			_rotate(skel, head_bone, conv, Basis(q))
	# --- Flexión por golpe (muelle amortiguado) ---
	_flinch_vel += (-170.0 * _flinch - 15.0 * _flinch_vel) * delta
	_flinch += _flinch_vel * delta
	var angle := _flinch.length()
	if chest_bone >= 0 and angle > 0.002:
		_rotate(skel, chest_bone, conv, Basis(_flinch / angle, minf(angle, 0.6)))


func _rotate(skel: Skeleton3D, bone: int, conv: Basis, local_rot: Basis) -> void:
	var pose := skel.get_bone_global_pose(bone)
	pose.basis = (conv * local_rot * conv.inverse()) * pose.basis
	skel.set_bone_global_pose(bone, pose)
