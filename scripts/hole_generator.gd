extends RefCounted

const GRID_X := 34
const GRID_Z := 58
const TEE_Z := 0.0
const TERRAIN_MARGIN := 8.0
const MAX_ATTEMPTS := 12
const GROUND_FRICTION := 0.82
const HEIGHT_BAND_SPACING := 0.42
const HEIGHT_BAND_WIDTH := 0.11
const HEIGHT_BAND_STRENGTH := 0.10
const HEIGHT_SHADE_STRENGTH := 0.16
const BLOCK_MIN_LENGTH := 4.5
const BLOCK_MAX_LENGTH := 8.5
const BLOCK_FORWARD_SLOPE := 0.030
const BLOCK_SIDE_SLOPE := 0.025
const GRID_LINE_STEP := 2
const GRID_LINE_LIFT := 0.055

func generate(seed_value: int) -> Dictionary:
	for attempt in MAX_ATTEMPTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value + attempt * 7919
		var params: Dictionary = _make_params(rng)
		params["blocks"] = _make_blocks(rng, params)
		var noise: FastNoiseLite = _make_noise(seed_value + attempt * 137)
		var tee := Vector3(0.0, _height_at(0.0, TEE_Z, params, noise), TEE_Z)
		var hole_length: float = params.holeLength
		var hole := Vector3(0.0, _height_at(0.0, -hole_length, params, noise), -hole_length)

		if _validate(params, noise, tee, hole):
			var root := Node3D.new()
			root.name = "GeneratedHole"
			root.add_child(_build_terrain(params, noise))
			root.add_child(_build_cup_marker(hole))

			return {
				"root": root,
				"tee_position": tee,
				"hole_position": hole,
				"seed": seed_value + attempt * 7919,
				"params": params,
				"safe_fairway": _make_safe_fairway(tee, hole, params),
			}

	push_warning("Hole validation failed; using the gentlest fallback.")
	var fallback: Dictionary = {
		"holeLength": 26.0,
		"widthBase": 10.0,
		"startHeight": 0.0,
		"endHeight": -0.35,
		"slopeStrength": 0.12,
		"curveAmount": 0.0,
		"holePlatformRadius": 2.8,
		"startPlatformRadius": 3.2,
		"edgeFalloff": 6.0,
		"noiseAmplitude": 0.02,
		"calmness": 1.0,
	}
	fallback["blocks"] = _make_fallback_blocks(fallback)
	var fallback_noise: FastNoiseLite = _make_noise(seed_value)
	var tee := Vector3(0.0, _height_at(0.0, TEE_Z, fallback, fallback_noise), TEE_Z)
	var hole_length: float = fallback.holeLength
	var hole := Vector3(0.0, _height_at(0.0, -hole_length, fallback, fallback_noise), -hole_length)
	var root := Node3D.new()
	root.name = "GeneratedHole"
	root.add_child(_build_terrain(fallback, fallback_noise))
	root.add_child(_build_cup_marker(hole))
	return {
		"root": root,
		"tee_position": tee,
		"hole_position": hole,
		"seed": seed_value,
		"params": fallback,
		"safe_fairway": _make_safe_fairway(tee, hole, fallback),
	}

func _make_params(rng: RandomNumberGenerator) -> Dictionary:
	var calmness: float = rng.randf_range(0.78, 1.0)
	return {
		"holeLength": rng.randf_range(24.0, 34.0),
		"widthBase": rng.randf_range(12.0, 15.0),
		"startHeight": rng.randf_range(-0.15, 0.15),
		"endHeight": rng.randf_range(-0.55, 0.55),
		"slopeStrength": rng.randf_range(0.10, 0.26),
		"curveAmount": 0.0,
		"holePlatformRadius": rng.randf_range(2.4, 3.2),
		"startPlatformRadius": rng.randf_range(3.0, 3.8),
		"edgeFalloff": rng.randf_range(6.5, 8.2),
		"noiseAmplitude": lerp(0.05, 0.015, calmness),
		"calmness": calmness,
	}

func _make_blocks(rng: RandomNumberGenerator, params: Dictionary) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var cursor := 0.0
	var block_index := 0
	var hole_length: float = params.holeLength

	while cursor < hole_length - 0.05:
		var remaining: float = hole_length - cursor
		var block_length: float = rng.randf_range(BLOCK_MIN_LENGTH, BLOCK_MAX_LENGTH)
		if remaining < BLOCK_MAX_LENGTH * 1.35:
			block_length = remaining
		else:
			block_length = min(block_length, remaining)

		var start_t: float = cursor / hole_length
		var end_t: float = (cursor + block_length) / hole_length
		var center_t: float = (start_t + end_t) * 0.5
		var anchor_amount := 1.0
		if center_t < 0.14 or center_t > 0.86:
			anchor_amount = 0.28

		var base_height: float = lerp(float(params.startHeight), float(params.endHeight), center_t)
		base_height += sin(center_t * PI) * float(params.slopeStrength) * 0.25
		base_height += rng.randf_range(-0.08, 0.08) * anchor_amount

		blocks.append({
			"index": block_index,
			"start_t": start_t,
			"end_t": end_t,
			"center_t": center_t,
			"center_z": -center_t * hole_length,
			"length": block_length,
			"width": float(params.widthBase) * rng.randf_range(0.86, 1.18),
			"base_height": base_height,
			"forward_slope": rng.randf_range(-BLOCK_FORWARD_SLOPE, BLOCK_FORWARD_SLOPE) * anchor_amount,
			"side_slope": rng.randf_range(-BLOCK_SIDE_SLOPE, BLOCK_SIDE_SLOPE) * anchor_amount,
			"tone": rng.randf(),
		})

		cursor += block_length
		block_index += 1

	return blocks

func _make_fallback_blocks(params: Dictionary) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var count := 5
	var hole_length: float = params.holeLength

	for index in count:
		var start_t := float(index) / float(count)
		var end_t := float(index + 1) / float(count)
		var center_t := (start_t + end_t) * 0.5
		var anchor_amount := 0.3 if center_t < 0.14 or center_t > 0.86 else 1.0
		blocks.append({
			"index": index,
			"start_t": start_t,
			"end_t": end_t,
			"center_t": center_t,
			"center_z": -center_t * hole_length,
			"length": hole_length / float(count),
			"width": float(params.widthBase),
			"base_height": lerp(float(params.startHeight), float(params.endHeight), center_t),
			"forward_slope": 0.012 * anchor_amount * (-1.0 if index % 2 == 0 else 1.0),
			"side_slope": 0.010 * anchor_amount * (-1.0 if index % 2 == 1 else 1.0),
			"tone": float(index) / float(max(1, count - 1)),
		})

	return blocks

func _make_noise(seed_value: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.09
	noise.fractal_octaves = 1
	return noise

func _make_safe_fairway(tee: Vector3, hole: Vector3, params: Dictionary) -> Dictionary:
	var approach_t := 0.82
	var approach := tee.lerp(hole, approach_t)
	var mid := tee.lerp(hole, 0.5)
	return {
		"center_start": tee,
		"center_mid": mid,
		"approach_point": approach,
		"center_end": hole,
		"safe_width": float(params.widthBase) * 0.78,
		"hole_length": float(params.holeLength),
	}

func _build_terrain(params: Dictionary, noise: FastNoiseLite) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Terrain"

	var width: float = params.widthBase + params.edgeFalloff * 2.0 + 12.0
	var min_x: float = -width * 0.5
	var max_x: float = width * 0.5
	var min_z: float = -float(params.holeLength) - TERRAIN_MARGIN
	var max_z: float = TERRAIN_MARGIN
	var dx: float = (max_x - min_x) / float(GRID_X - 1)
	var dz: float = (max_z - min_z) / float(GRID_Z - 1)

	var points: Array[Array] = []
	var height_data := PackedFloat32Array()
	for z_i in GRID_Z:
		var row: Array[Vector3] = []
		var z: float = min_z + dz * z_i
		for x_i in GRID_X:
			var x: float = min_x + dx * x_i
			var height := _height_at(x, z, params, noise)
			row.append(Vector3(x, height, z))
			height_data.append(height)
		points.append(row)

	var faces := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for z_i in GRID_Z - 1:
		for x_i in GRID_X - 1:
			var a: Vector3 = points[z_i][x_i]
			var b: Vector3 = points[z_i][x_i + 1]
			var c: Vector3 = points[z_i + 1][x_i]
			var d: Vector3 = points[z_i + 1][x_i + 1]
			_add_triangle(st, faces, a, c, b, params)
			_add_triangle(st, faces, b, c, d, params)

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "GroundMesh"
	mesh_instance.mesh = mesh
	mesh_instance.set_surface_override_material(0, material)
	holder.add_child(mesh_instance)
	holder.add_child(_build_grid_lines(points))

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = GROUND_FRICTION
	physics_material.bounce = 0.0
	body.physics_material_override = physics_material

	var shape := HeightMapShape3D.new()
	shape.map_width = GRID_X
	shape.map_depth = GRID_Z
	shape.map_data = height_data
	var collision := CollisionShape3D.new()
	collision.name = "GroundCollision"
	collision.shape = shape
	collision.position = Vector3((min_x + max_x) * 0.5, 0.0, (min_z + max_z) * 0.5)
	collision.scale = Vector3(dx, 1.0, dz)
	body.add_child(collision)
	holder.add_child(body)

	return holder

func _build_grid_lines(points: Array[Array]) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var lift := Vector3.UP * GRID_LINE_LIFT

	for z_i in range(0, GRID_Z, GRID_LINE_STEP):
		for x_i in GRID_X - 1:
			st.add_vertex(points[z_i][x_i] + lift)
			st.add_vertex(points[z_i][x_i + 1] + lift)

	for x_i in range(0, GRID_X, GRID_LINE_STEP):
		for z_i in GRID_Z - 1:
			st.add_vertex(points[z_i][x_i] + lift)
			st.add_vertex(points[z_i + 1][x_i] + lift)

	var lines := MeshInstance3D.new()
	lines.name = "CyberGrid"
	lines.mesh = st.commit()

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.86, 0.92, 0.36)
	material.emission_enabled = true
	material.emission = Color(0.18, 0.55, 0.70, 1.0)
	material.emission_energy_multiplier = 0.55
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.material_override = material
	return lines

func _add_triangle(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, params: Dictionary) -> void:
	for point in [a, b, c]:
		st.set_color(_terrain_color_at(point, params))
		st.add_vertex(point)
		faces.append(point)

func _build_cup_marker(hole_position: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.04, 0.045, 0.04, 1.0)
	material.roughness = 1.0

	var disk := MeshInstance3D.new()
	disk.name = "Cup"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.58
	mesh.bottom_radius = 0.58
	mesh.height = 0.035
	mesh.radial_segments = 32
	disk.mesh = mesh
	disk.material_override = material
	disk.position = hole_position + Vector3.UP * 0.02
	return disk

func _height_at(x: float, z: float, params: Dictionary, noise: FastNoiseLite) -> float:
	var t: float = clamp((-z) / float(params.holeLength), 0.0, 1.0)
	var block: Dictionary = _block_at_t(t, params)
	var base_height: float = _block_plane_height(x, z, block)
	var lateral: float = abs(x - _center_x_at(t, params))
	var half_width: float = _half_width_at(t, params)
	var outside: float = max(0.0, lateral - half_width)
	var edge_t: float = clamp(outside / float(params.edgeFalloff), 0.0, 1.0)
	var edge_drop: float = -1.18 * _smooth01(edge_t)
	var surface_noise: float = noise.get_noise_2d(x, z) * float(params.noiseAmplitude)
	var height: float = base_height + edge_drop + surface_noise

	height = _flatten_platform(height, x, z, Vector2(0.0, TEE_Z), params.startHeight, params.startPlatformRadius)
	height = _flatten_platform(height, x, z, Vector2(0.0, -params.holeLength), params.endHeight, params.holePlatformRadius)
	return height

func _block_at_t(t: float, params: Dictionary) -> Dictionary:
	var blocks: Array = params.blocks
	for block in blocks:
		if t <= float(block.end_t):
			return block
	return blocks[blocks.size() - 1]

func _block_plane_height(x: float, z: float, block: Dictionary) -> float:
	var z_offset: float = z - float(block.center_z)
	return float(block.base_height) + z_offset * float(block.forward_slope) + x * float(block.side_slope)

func _flatten_platform(height: float, x: float, z: float, center: Vector2, target_height: float, radius: float) -> float:
	var distance: float = Vector2(x, z).distance_to(center)
	var flat_amount: float = 1.0 - _smooth01(clamp((distance - radius) / 2.4, 0.0, 1.0))
	return lerp(height, target_height, flat_amount)

func _center_x_at(t: float, params: Dictionary) -> float:
	return sin((t - 0.5) * PI) * params.curveAmount

func _half_width_at(t: float, params: Dictionary) -> float:
	var block: Dictionary = _block_at_t(t, params)
	return lerp(float(block.width) * 0.60, float(block.width) * 0.52, t)

func _terrain_color_at(point: Vector3, params: Dictionary) -> Color:
	var x := point.x
	var z := point.z
	var t: float = clamp((-z) / float(params.holeLength), 0.0, 1.0)
	var block: Dictionary = _block_at_t(t, params)
	var lateral: float = abs(x - _center_x_at(t, params))
	var half_width: float = _half_width_at(t, params)
	var edge_amount: float = clamp((lateral - half_width * 0.75) / (float(params.edgeFalloff) + 0.1), 0.0, 1.0)
	var slope_vector := Vector2(float(block.side_slope), float(block.forward_slope))
	var slope_amount: float = clamp(slope_vector.length() / 0.055, 0.0, 1.0)
	var orientation: float = atan2(slope_vector.x, slope_vector.y)
	var cyan := Color(0.18, 0.78, 0.88, 1.0)
	var violet := Color(0.54, 0.36, 0.90, 1.0)
	var rose := Color(0.93, 0.38, 0.72, 1.0)
	var orientation_mix: float = (sin(orientation + float(block.tone) * TAU) + 1.0) * 0.5
	var accent := cyan.lerp(violet, orientation_mix)
	accent = accent.lerp(rose, max(0.0, cos(orientation) * 0.35))
	var base := Color(0.13, 0.20, 0.33, 1.0)
	var color := base.lerp(accent, 0.34 + slope_amount * 0.28)
	var edge := Color(0.08, 0.11, 0.20, 1.0)
	color = color.lerp(edge, _smooth01(edge_amount) * 0.52)

	var height_t: float = clamp((point.y + 1.6) / 2.8, 0.0, 1.0)
	color = color.lerp(Color(0.55, 0.86, 0.95, 1.0), height_t * HEIGHT_SHADE_STRENGTH)

	var band_phase: float = fposmod(point.y, HEIGHT_BAND_SPACING) / HEIGHT_BAND_SPACING
	var band_distance: float = min(band_phase, 1.0 - band_phase)
	var band_amount: float = 1.0 - _smooth01(clamp(band_distance / HEIGHT_BAND_WIDTH, 0.0, 1.0))
	return color.lerp(Color(0.76, 0.92, 1.0, 1.0), band_amount * HEIGHT_BAND_STRENGTH)

func _validate(params: Dictionary, noise: FastNoiseLite, tee: Vector3, hole: Vector3) -> bool:
	if params.holeLength < 22.0 or params.widthBase < 8.0:
		return false

	var height_delta: float = abs(hole.y - tee.y)
	if height_delta / float(params.holeLength) > 0.055:
		return false

	var step: float = float(params.holeLength) / 12.0
	var last_height: float = _height_at(0.0, TEE_Z, params, noise)
	for i in range(1, 13):
		var z: float = -step * i
		var height: float = _height_at(0.0, z, params, noise)
		if abs(height - last_height) / step > 0.145:
			return false
		last_height = height

	var cup_left: float = _height_at(-1.2, -float(params.holeLength), params, noise)
	var cup_right: float = _height_at(1.2, -float(params.holeLength), params, noise)
	if abs(cup_left - cup_right) > 0.08:
		return false

	return true

func _smooth01(value: float) -> float:
	var x: float = clamp(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
