extends Node3D

const HoleGenerator := preload("res://scripts/hole_generator.gd")

enum ShotMode { PUSH, HIT }

const BALL_RADIUS := 0.34
const CUP_RADIUS := 0.72
const PUSH_POWER := 10.8
const PUSH_UP_POWER := 0.12
const HIT_FORWARD_POWER := 8.0
const HIT_UP_POWER := 5.6
const BALL_FRICTION := 0.62
const BALL_BOUNCE := 0.28
const BALL_LINEAR_DAMP := 0.52
const BALL_ANGULAR_DAMP := 0.95
const CHARGE_SECONDS := 1.15
const RESHOT_DELAY_SECONDS := 2.0
const AIM_TURN_SPEED := 1.55
const START_SEED := 1001
const CAMERA_BACK_DISTANCE := 8.5
const CAMERA_HEIGHT := 6.7
const CAMERA_LOOK_AHEAD := 0.24
const CAMERA_LOOK_HEIGHT := 0.65
const CAMERA_FOLLOW_SMOOTHNESS := 2.2
const GROUND_MARKER_MAX_HEIGHT := 5.0
const GROUND_MARKER_MIN_ALPHA := 0.16
const GROUND_MARKER_MAX_ALPHA := 0.58
const GROUND_MARKER_MIN_SCALE := 0.58
const GROUND_MARKER_MAX_SCALE := 1.0
const GROUND_MARKER_LIFT := 0.085
const HEIGHT_LINE_MIN_HEIGHT := 0.28
const AIM_MARKER_COUNT := 8
const AIM_MARKER_START_DISTANCE := 0.76
const AIM_MARKER_MIN_REACH := 1.35
const AIM_MARKER_MAX_REACH := 4.8
const AIM_MARKER_LIFT := 0.095
const AIM_MARKER_NEAR_ALPHA := 0.40
const AIM_MARKER_FAR_ALPHA := 0.12
const AUTOPLAY_ARG := "--autoplay-test"
const AUTOPLAY_TARGET_HOLES := 3
const AUTOPLAY_TIMEOUT_SECONDS := 240.0
const AUTOPLAY_MAX_STROKES_PER_HOLE := 24
const AUTOPLAY_SETTLE_SECONDS := 0.18

var generator := HoleGenerator.new()
var hole_root: Node3D
var ball: RigidBody3D
var camera: Camera3D
var strokes_label: Label
var mode_label: Label
var aim_markers: Array[MeshInstance3D] = []
var aim_marker_materials: Array[StandardMaterial3D] = []
var ball_aura: MeshInstance3D
var ball_core_material: StandardMaterial3D
var ball_aura_material: StandardMaterial3D
var ground_marker: MeshInstance3D
var ground_marker_material: StandardMaterial3D
var height_line: MeshInstance3D
var height_line_material: StandardMaterial3D
var world_environment: WorldEnvironment

var tee_position := Vector3.ZERO
var cup_position := Vector3.ZERO
var current_hole_seed := START_SEED
var current_hole_params: Dictionary = {}
var current_safe_fairway: Dictionary = {}
var current_seed := START_SEED
var hole_number := 1
var strokes := 0
var aim_angle := 0.0
var charge := 0.0
var time_since_last_shot := INF
var shot_mode := ShotMode.PUSH
var is_charging := false
var completing_hole := false

var autoplay_test := false
var autoplay_finished := false
var autoplay_completed_holes := 0
var autoplay_elapsed := 0.0
var autoplay_hole_elapsed := 0.0
var autoplay_settled_time := 0.0
var autoplay_charge_target := 0.0
var autoplay_last_shot_distance := 0.0
var autoplay_records: Array[String] = []

func _ready() -> void:
	autoplay_test = _has_user_arg(AUTOPLAY_ARG)
	if autoplay_test:
		print("AUTOPLAY start: target=%d holes" % AUTOPLAY_TARGET_HOLES)

	_setup_world()
	_setup_ball()
	_setup_ground_cues()
	_setup_aim_markers()
	_setup_ui()
	_start_hole(current_seed)

func _physics_process(delta: float) -> void:
	_update_reshot_timer(delta)
	_update_aim(delta)
	_update_charge(delta)
	_update_ball_visuals()
	_update_aim_markers()
	_update_ground_cues()
	_update_camera(delta)
	_check_hole_complete()
	_update_autoplay(delta)

	if ball and ball.global_position.y < -8.0:
		if autoplay_test:
			_finish_autoplay_failure("ball fell below terrain")
			return
		_reset_ball()

func _unhandled_input(event: InputEvent) -> void:
	if autoplay_test:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_charge()
		else:
			_release_shot()

	if event is InputEventMouseMotion and is_charging:
		aim_angle -= event.relative.x * 0.006

	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_SPACE:
			if event.pressed:
				_begin_charge()
			else:
				_release_shot()
		elif event.pressed and event.keycode == KEY_TAB:
			_toggle_shot_mode()
		elif event.pressed and event.keycode == KEY_R:
			_start_hole(current_seed)

func _setup_world() -> void:
	world_environment = WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.08, 0.16, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.34, 0.42, 0.62, 1.0)
	environment.ambient_light_energy = 1.15
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "SoftSun"
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	add_child(sun)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 45.0
	camera.current = true
	add_child(camera)

func _setup_ball() -> void:
	ball = RigidBody3D.new()
	ball.name = "Ball"
	ball.mass = 0.65
	ball.linear_damp = BALL_LINEAR_DAMP
	ball.angular_damp = BALL_ANGULAR_DAMP
	ball.continuous_cd = true

	var physics_material := PhysicsMaterial.new()
	physics_material.friction = BALL_FRICTION
	physics_material.bounce = BALL_BOUNCE
	ball.physics_material_override = physics_material

	var collision := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = BALL_RADIUS
	collision.shape = sphere_shape
	ball.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = BALL_RADIUS
	sphere_mesh.height = BALL_RADIUS * 2.0
	sphere_mesh.radial_segments = 24
	sphere_mesh.rings = 12
	mesh_instance.mesh = sphere_mesh

	ball_core_material = StandardMaterial3D.new()
	ball_core_material.roughness = 0.52
	ball_core_material.emission_enabled = true
	mesh_instance.material_override = ball_core_material
	ball.add_child(mesh_instance)

	ball_aura = MeshInstance3D.new()
	ball_aura.name = "BallAura"
	var aura_mesh := SphereMesh.new()
	aura_mesh.radius = BALL_RADIUS * 1.18
	aura_mesh.height = BALL_RADIUS * 2.36
	aura_mesh.radial_segments = 32
	aura_mesh.rings = 16
	ball_aura.mesh = aura_mesh
	ball_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	ball_aura_material = StandardMaterial3D.new()
	ball_aura_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball_aura_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ball_aura_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball_aura_material.emission_enabled = true
	ball_aura.material_override = ball_aura_material
	ball.add_child(ball_aura)

	add_child(ball)
	_update_ball_visuals()

func _setup_ground_cues() -> void:
	ground_marker = MeshInstance3D.new()
	ground_marker.name = "GroundContact"
	ground_marker.mesh = _make_ground_ring_mesh(BALL_RADIUS * 1.12, BALL_RADIUS * 1.72, 64)
	ground_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	ground_marker_material = StandardMaterial3D.new()
	ground_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ground_marker_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ground_marker_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_marker_material.emission_enabled = true
	ground_marker.material_override = ground_marker_material
	add_child(ground_marker)

	height_line = MeshInstance3D.new()
	height_line.name = "HeightLine"
	var line_mesh := CylinderMesh.new()
	line_mesh.top_radius = 0.018
	line_mesh.bottom_radius = 0.018
	line_mesh.height = 1.0
	line_mesh.radial_segments = 12
	height_line.mesh = line_mesh
	height_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	height_line_material = StandardMaterial3D.new()
	height_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	height_line_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	height_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	height_line_material.emission_enabled = true
	height_line.material_override = height_line_material
	height_line.visible = false
	add_child(height_line)

func _make_ground_ring_mesh(inner_radius: float, outer_radius: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for index in segments:
		var angle_a := TAU * float(index) / float(segments)
		var angle_b := TAU * float(index + 1) / float(segments)
		var inner_a := Vector3(cos(angle_a) * inner_radius, 0.0, sin(angle_a) * inner_radius)
		var outer_a := Vector3(cos(angle_a) * outer_radius, 0.0, sin(angle_a) * outer_radius)
		var inner_b := Vector3(cos(angle_b) * inner_radius, 0.0, sin(angle_b) * inner_radius)
		var outer_b := Vector3(cos(angle_b) * outer_radius, 0.0, sin(angle_b) * outer_radius)

		st.add_vertex(outer_a)
		st.add_vertex(inner_a)
		st.add_vertex(outer_b)
		st.add_vertex(outer_b)
		st.add_vertex(inner_a)
		st.add_vertex(inner_b)

	return st.commit()

func _setup_aim_markers() -> void:
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.13
	marker_mesh.bottom_radius = 0.13
	marker_mesh.height = 0.014
	marker_mesh.radial_segments = 24

	for index in AIM_MARKER_COUNT:
		var marker := MeshInstance3D.new()
		marker.name = "AimMarker%d" % (index + 1)
		marker.mesh = marker_mesh
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.visible = false

		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		marker.material_override = material

		aim_markers.append(marker)
		aim_marker_materials.append(material)
		add_child(marker)

func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MinimalUI"
	add_child(layer)

	strokes_label = Label.new()
	strokes_label.position = Vector2(22.0, 18.0)
	strokes_label.add_theme_font_size_override("font_size", 22)
	strokes_label.add_theme_color_override("font_color", Color(0.93, 0.94, 0.88, 0.88))
	layer.add_child(strokes_label)

	mode_label = Label.new()
	mode_label.position = Vector2(22.0, 46.0)
	mode_label.add_theme_font_size_override("font_size", 16)
	mode_label.add_theme_color_override("font_color", Color(0.58, 0.88, 1.0, 0.78))
	layer.add_child(mode_label)
	_update_mode_label()

func _start_hole(seed_value: int) -> void:
	if hole_root:
		hole_root.queue_free()

	var hole: Dictionary = generator.generate(seed_value)
	hole_root = hole.root
	add_child(hole_root)
	move_child(hole_root, 0)

	tee_position = hole.tee_position
	cup_position = hole.hole_position
	current_hole_seed = int(hole.seed)
	current_hole_params = hole.params
	current_safe_fairway = hole.safe_fairway
	strokes = 0
	charge = 0.0
	time_since_last_shot = INF
	is_charging = false
	completing_hole = false

	var direction := (cup_position - tee_position)
	direction.y = 0.0
	direction = direction.normalized()
	aim_angle = atan2(direction.x, -direction.z)

	_reset_ball()
	_place_camera_initial()
	_update_strokes_label()

	if autoplay_test:
		_reset_autoplay_hole_state()

func _reset_ball() -> void:
	ball.freeze = true
	ball.sleeping = false
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = tee_position + Vector3.UP * (BALL_RADIUS + 0.08)
	ball.freeze = false
	time_since_last_shot = INF

func _begin_charge(reset_to_camera := true) -> void:
	if not _can_shoot():
		return
	if reset_to_camera:
		aim_angle = _camera_forward_aim_angle()
	is_charging = true
	charge = 0.0

func _release_shot() -> void:
	if not is_charging:
		return
	is_charging = false

	if not _can_shoot():
		charge = 0.0
		return

	var settled_charge: float = clamp(charge, 0.0, 1.0)
	var impulse := _shot_impulse_for_charge(settled_charge)
	ball.apply_central_impulse(impulse)
	strokes += 1
	charge = 0.0
	time_since_last_shot = 0.0
	_update_strokes_label()

func _update_reshot_timer(delta: float) -> void:
	if completing_hole:
		return
	time_since_last_shot += delta

func _update_aim(delta: float) -> void:
	if completing_hole:
		return
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		aim_angle -= AIM_TURN_SPEED * delta
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		aim_angle += AIM_TURN_SPEED * delta

func _update_charge(delta: float) -> void:
	if is_charging:
		charge = clamp(charge + delta / CHARGE_SECONDS, 0.0, 1.0)

func _update_ball_visuals() -> void:
	if not ball_core_material or not ball_aura_material or not ball_aura:
		return

	var accent := _shot_mode_accent_color()
	var core := _shot_mode_core_color()
	var charge_t := charge if is_charging else 0.0
	var aura_alpha: float = lerp(0.20, 0.32, charge_t)
	var aura_energy: float = lerp(0.62, 0.92, charge_t)
	var core_energy: float = lerp(1.15, 1.55, charge_t)

	ball_core_material.albedo_color = core
	ball_core_material.emission = accent.lerp(core, 0.55)
	ball_core_material.emission_energy_multiplier = core_energy

	ball_aura.scale = Vector3.ONE * lerp(1.0, 1.08, charge_t)
	ball_aura_material.albedo_color = Color(accent.r, accent.g, accent.b, aura_alpha)
	ball_aura_material.emission = accent
	ball_aura_material.emission_energy_multiplier = aura_energy

func _update_aim_markers() -> void:
	var can_show := _can_shoot() or is_charging
	if not can_show or completing_hole:
		_hide_aim_markers()
		return

	var charge_t: float = max(charge, 0.08 if is_charging else 0.0)
	var marker_count: int = clampi(int(round(lerp(3.0, float(AIM_MARKER_COUNT), charge_t))), 3, AIM_MARKER_COUNT)
	var reach: float = lerp(AIM_MARKER_MIN_REACH, AIM_MARKER_MAX_REACH, charge_t)
	var direction := _aim_direction()
	var accent := _shot_mode_accent_color()

	for index in AIM_MARKER_COUNT:
		var marker: MeshInstance3D = aim_markers[index]
		var material: StandardMaterial3D = aim_marker_materials[index]
		if index >= marker_count:
			marker.visible = false
			continue

		var marker_t: float = float(index + 1) / float(marker_count)
		var distance: float = lerp(AIM_MARKER_START_DISTANCE, reach, marker_t)
		var sample_position: Vector3 = ball.global_position + direction * distance
		var query := PhysicsRayQueryParameters3D.create(
			sample_position + Vector3.UP * 4.0,
			sample_position + Vector3.DOWN * 10.0
		)
		query.exclude = [ball.get_rid()]

		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			marker.visible = false
			continue

		var alpha: float = lerp(AIM_MARKER_NEAR_ALPHA, AIM_MARKER_FAR_ALPHA, marker_t) * lerp(0.78, 1.0, charge_t)
		var marker_scale: float = lerp(0.92, 0.50, marker_t)
		marker.visible = true
		marker.global_position = Vector3(hit.position.x, hit.position.y + AIM_MARKER_LIFT, hit.position.z)
		marker.rotation = Vector3(0.0, aim_angle, 0.0)
		marker.scale = Vector3(marker_scale * 0.72, 1.0, marker_scale * 1.35)
		material.albedo_color = Color(accent.r, accent.g, accent.b, alpha)
		material.emission = accent
		material.emission_energy_multiplier = lerp(0.48, 0.28, marker_t)

func _hide_aim_markers() -> void:
	for marker in aim_markers:
		marker.visible = false

func _update_ground_cues() -> void:
	if not ball or not ground_marker or not height_line:
		return

	var query := PhysicsRayQueryParameters3D.create(
		ball.global_position + Vector3.UP * 0.6,
		ball.global_position + Vector3.DOWN * 12.0
	)
	query.exclude = [ball.get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		ground_marker.visible = false
		height_line.visible = false
		return

	var ground_position: Vector3 = hit.position
	var height_above_ground: float = max(0.0, ball.global_position.y - ground_position.y - BALL_RADIUS)
	var height_t: float = clamp(height_above_ground / GROUND_MARKER_MAX_HEIGHT, 0.0, 1.0)
	var marker_alpha: float = lerp(GROUND_MARKER_MAX_ALPHA, GROUND_MARKER_MIN_ALPHA, height_t)
	var marker_scale: float = lerp(GROUND_MARKER_MAX_SCALE, GROUND_MARKER_MIN_SCALE, height_t)
	var accent := _shot_mode_accent_color()

	ground_marker.visible = true
	ground_marker.global_position = ground_position + Vector3.UP * GROUND_MARKER_LIFT
	ground_marker.scale = Vector3(marker_scale, 1.0, marker_scale)
	ground_marker_material.albedo_color = Color(accent.r, accent.g, accent.b, marker_alpha)
	ground_marker_material.emission = accent
	ground_marker_material.emission_energy_multiplier = lerp(0.78, 0.42, height_t)

	if height_above_ground <= HEIGHT_LINE_MIN_HEIGHT:
		height_line.visible = false
		return

	var line_length: float = max(0.05, height_above_ground - GROUND_MARKER_LIFT)
	var line_alpha: float = lerp(0.42, 0.24, height_t)
	height_line.visible = true
	height_line.global_position = ground_position + Vector3.UP * (GROUND_MARKER_LIFT + line_length * 0.5)
	height_line.scale = Vector3(1.0, line_length, 1.0)
	height_line_material.albedo_color = Color(accent.r, accent.g, accent.b, line_alpha)
	height_line_material.emission = accent
	height_line_material.emission_energy_multiplier = 0.62

func _update_camera(delta: float) -> void:
	if not camera or not ball:
		return

	var target_position := _camera_position_for_anchor(ball.global_position)
	var look_target := _camera_look_target(ball.global_position)

	camera.global_position = camera.global_position.lerp(target_position, min(delta * CAMERA_FOLLOW_SMOOTHNESS, 1.0))
	camera.look_at(look_target, Vector3.UP)

func _place_camera_initial() -> void:
	var anchor := ball.global_position if ball else tee_position
	camera.global_position = _camera_position_for_anchor(anchor)
	camera.look_at(_camera_look_target(anchor), Vector3.UP)

func _camera_position_for_anchor(anchor: Vector3) -> Vector3:
	var direction := cup_position - anchor
	direction.y = 0.0
	if direction.length() < 0.1:
		direction = _aim_direction()
	else:
		direction = direction.normalized()
	return anchor - direction * CAMERA_BACK_DISTANCE + Vector3.UP * CAMERA_HEIGHT

func _camera_look_target(anchor: Vector3) -> Vector3:
	return anchor.lerp(cup_position, CAMERA_LOOK_AHEAD) + Vector3.UP * CAMERA_LOOK_HEIGHT

func _check_hole_complete() -> void:
	if completing_hole or not ball:
		return

	var flat_ball := Vector2(ball.global_position.x, ball.global_position.z)
	var flat_cup := Vector2(cup_position.x, cup_position.z)
	if flat_ball.distance_to(flat_cup) <= CUP_RADIUS and ball.linear_velocity.length() < 2.4:
		call_deferred("_complete_hole")

func _complete_hole() -> void:
	if completing_hole:
		return

	var finished_hole_number := hole_number
	var finished_seed := current_hole_seed
	var finished_strokes := strokes
	var finished_time := autoplay_hole_elapsed

	completing_hole = true
	is_charging = false
	_hide_aim_markers()
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.freeze = true

	await get_tree().create_timer(0.75).timeout

	if autoplay_test:
		autoplay_completed_holes += 1
		var record := "hole=%d seed=%d strokes=%d time=%.2fs" % [
			finished_hole_number,
			finished_seed,
			finished_strokes,
			finished_time,
		]
		autoplay_records.append(record)
		print("AUTOPLAY holed: %s" % record)

		if autoplay_completed_holes >= AUTOPLAY_TARGET_HOLES:
			_finish_autoplay_success()
			return

	hole_number += 1
	current_seed += 1
	_start_hole(current_seed)

func _can_shoot() -> bool:
	if completing_hole or not ball:
		return false
	var ball_settled := ball.linear_velocity.length() < 0.22 and ball.angular_velocity.length() < 0.9
	var reshot_ready := time_since_last_shot >= RESHOT_DELAY_SECONDS
	return ball_settled or reshot_ready

func _aim_direction() -> Vector3:
	return Vector3(sin(aim_angle), 0.0, -cos(aim_angle)).normalized()

func _camera_forward_aim_angle() -> float:
	if not camera:
		return aim_angle
	var direction := -camera.global_transform.basis.z
	direction.y = 0.0
	if direction.length() < 0.01:
		return aim_angle
	direction = direction.normalized()
	return atan2(direction.x, -direction.z)

func _update_strokes_label() -> void:
	strokes_label.text = "Hole %d   Strokes %d" % [hole_number, strokes]

func _toggle_shot_mode() -> void:
	if shot_mode == ShotMode.PUSH:
		shot_mode = ShotMode.HIT
	else:
		shot_mode = ShotMode.PUSH
	_update_mode_label()
	_update_ball_visuals()

func _update_mode_label() -> void:
	if not mode_label:
		return
	mode_label.text = "HIT" if shot_mode == ShotMode.HIT else "PUSH"

func _shot_mode_accent_color() -> Color:
	if shot_mode == ShotMode.HIT:
		return Color(1.0, 0.34, 0.88, 1.0)
	return Color(0.28, 0.95, 1.0, 1.0)

func _shot_mode_core_color() -> Color:
	if shot_mode == ShotMode.HIT:
		return Color(1.0, 0.84, 0.97, 1.0)
	return Color(0.86, 1.0, 1.0, 1.0)

func _shot_impulse_for_charge(settled_charge: float) -> Vector3:
	var shot_scale: float = lerp(0.08, 1.0, settled_charge)
	var direction := _aim_direction()
	if shot_mode == ShotMode.HIT:
		return direction * HIT_FORWARD_POWER * shot_scale + Vector3.UP * HIT_UP_POWER * shot_scale
	return direction * PUSH_POWER * shot_scale + Vector3.UP * PUSH_UP_POWER * shot_scale

func _has_user_arg(argument: String) -> bool:
	return OS.get_cmdline_user_args().has(argument) or OS.get_cmdline_args().has(argument)

func _reset_autoplay_hole_state() -> void:
	autoplay_hole_elapsed = 0.0
	autoplay_settled_time = 0.0
	autoplay_charge_target = 0.0
	autoplay_last_shot_distance = _flat_distance_to_cup()

	var length := 0.0
	if current_safe_fairway.has("hole_length"):
		length = float(current_safe_fairway.hole_length)

	print("AUTOPLAY hole %d seed=%d length=%.2f start_distance=%.2f" % [
		hole_number,
		current_hole_seed,
		length,
		autoplay_last_shot_distance,
	])

func _update_autoplay(delta: float) -> void:
	if not autoplay_test or autoplay_finished:
		return

	autoplay_elapsed += delta
	autoplay_hole_elapsed += delta

	if autoplay_elapsed > AUTOPLAY_TIMEOUT_SECONDS:
		_finish_autoplay_failure("timeout after %.2fs" % autoplay_elapsed)
		return

	if strokes > AUTOPLAY_MAX_STROKES_PER_HOLE:
		_finish_autoplay_failure("too many strokes on hole %d" % hole_number)
		return

	if completing_hole:
		return

	if is_charging:
		if charge >= autoplay_charge_target:
			_release_shot()
			autoplay_settled_time = 0.0
		return

	if not _can_shoot():
		autoplay_settled_time = 0.0
		return

	autoplay_settled_time += delta
	if autoplay_settled_time < AUTOPLAY_SETTLE_SECONDS:
		return

	_take_autoplay_shot()

func _take_autoplay_shot() -> void:
	var distance := _flat_distance_to_cup()
	if distance <= CUP_RADIUS:
		return

	var shot := _choose_autoplay_shot(distance)
	var target: Vector3 = shot.target
	aim_angle = _angle_to_point(target)
	autoplay_charge_target = float(shot.charge)
	autoplay_last_shot_distance = distance

	print("AUTOPLAY shot hole=%d stroke=%d distance=%.2f charge=%.3f" % [
		hole_number,
		strokes + 1,
		distance,
		autoplay_charge_target,
	])

	_begin_charge(false)
	if not is_charging:
		_finish_autoplay_failure("could not start shot")
		return

	if autoplay_charge_target <= 0.001:
		_release_shot()
		autoplay_settled_time = 0.0

func _choose_autoplay_shot(distance: float) -> Dictionary:
	var target := cup_position
	var planned_distance := distance

	if distance > 15.0:
		planned_distance = min(distance - 4.0, 14.0)
		target = _point_toward_cup(planned_distance)
	elif distance > 8.0:
		planned_distance = min(distance - 2.5, 8.5)
		target = _point_toward_cup(planned_distance)

	var height_delta := cup_position.y - ball.global_position.y
	var charge_for_distance := _charge_for_distance(planned_distance)
	var uphill_bias: float = clamp(height_delta * 0.08, -0.04, 0.06)
	var charge_value: float = clamp(charge_for_distance + uphill_bias, 0.0, 1.0)

	if distance < 2.4:
		charge_value = min(charge_value, 0.06)
	elif distance < 4.0:
		charge_value = min(charge_value, 0.15)

	return {
		"target": target,
		"charge": charge_value,
	}

func _charge_for_distance(distance: float) -> float:
	var desired_impulse := distance / 1.48
	return clamp(((desired_impulse / PUSH_POWER) - 0.08) / 0.92, 0.0, 1.0)

func _point_toward_cup(distance: float) -> Vector3:
	var direction := cup_position - ball.global_position
	direction.y = 0.0
	if direction.length() < 0.01:
		return cup_position
	direction = direction.normalized()
	var point := ball.global_position + direction * distance
	return Vector3(point.x, ball.global_position.y, point.z)

func _angle_to_point(target: Vector3) -> float:
	var direction := target - ball.global_position
	direction.y = 0.0
	if direction.length() < 0.01:
		direction = cup_position - ball.global_position
		direction.y = 0.0
	if direction.length() < 0.01:
		return aim_angle
	direction = direction.normalized()
	return atan2(direction.x, -direction.z)

func _flat_distance_to_cup() -> float:
	if not ball:
		return INF
	return Vector2(ball.global_position.x, ball.global_position.z).distance_to(Vector2(cup_position.x, cup_position.z))

func _finish_autoplay_success() -> void:
	if autoplay_finished:
		return
	autoplay_finished = true
	print("AUTOPLAY PASS: completed %d holes in %.2fs" % [autoplay_completed_holes, autoplay_elapsed])
	for record in autoplay_records:
		print("AUTOPLAY record: %s" % record)
	get_tree().quit(0)

func _finish_autoplay_failure(reason: String) -> void:
	if autoplay_finished:
		return
	autoplay_finished = true
	push_error("AUTOPLAY FAIL: %s" % reason)
	for record in autoplay_records:
		print("AUTOPLAY record: %s" % record)
	get_tree().quit(1)
