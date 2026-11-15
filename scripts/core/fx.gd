extends Node
## =====================================================================
##  FX.GD - efecte vizuale și unelte pentru forme 3D (autoload: FX)
## =====================================================================
##  - particule (exploziile mici de la sărituri, monede etc.)
##  - tremuratul camerei ("trauma"), flash pe ecran, text care plutește
##  - materiale (culori) refolosite și funcții care creează forme simple
##    (cutie, sferă, cilindru, inel, capsulă) - din ele e făcut tot jocul.
## =====================================================================

const BURST_COUNT := 24        # câte explozii de particule pot exista simultan
const BURST_MAX_PARTICLES := 32

var trauma := 0.0              # 0..1: cât de tare tremură camera acum
var material_cache := {}       # aceeași culoare = același material (mai rapid)
var bursts: Array[GPUParticles3D] = []
var next_burst := 0
var flash_rect: ColorRect
var particle_mesh: SphereMesh
var particle_material: StandardMaterial3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	create_flash_overlay()
	create_particle_look()
	for i in BURST_COUNT:
		var burst_emitter := make_emitter(Color.WHITE, BURST_MAX_PARTICLES, 0.7, Vector3.UP, 180.0, 3.0, 7.0, Vector3(0, -9, 0), 0.3)
		burst_emitter.one_shot = true
		burst_emitter.explosiveness = 1.0   # toate particulele pornesc deodată
		burst_emitter.emitting = false
		add_child(burst_emitter)
		bursts.append(burst_emitter)


func create_flash_overlay() -> void:
	# Un dreptunghi pe tot ecranul, invizibil, pe care îl colorăm o clipă.
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash_rect)


func create_particle_look() -> void:
	particle_mesh = SphereMesh.new()
	particle_mesh.radius = 0.5
	particle_mesh.height = 1.0
	particle_mesh.radial_segments = 6
	particle_mesh.rings = 3
	particle_material = StandardMaterial3D.new()
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true


func _process(delta: float) -> void:
	trauma = maxf(trauma - delta * 1.8, 0.0)   # tremuratul se stinge singur


# =====================================================================
#  PARTICULE
# =====================================================================
## Creează un emițător de particule continuu. Cine îl cere îl adaugă în scenă.
func make_emitter(color: Color, amount: int, lifetime: float, direction: Vector3, spread: float,
		speed_min: float, speed_max: float, gravity: Vector3, size: float, box := Vector3.ZERO) -> GPUParticles3D:
	var settings := ParticleProcessMaterial.new()
	settings.direction = direction
	settings.spread = spread
	settings.initial_velocity_min = speed_min
	settings.initial_velocity_max = speed_max
	settings.gravity = gravity
	settings.scale_min = size * 0.6
	settings.scale_max = size * 1.4
	settings.damping_min = 0.5
	settings.damping_max = 2.0
	settings.color = color
	if box != Vector3.ZERO:   # particulele apar într-o cutie, nu într-un punct
		settings.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		settings.emission_box_extents = box
	settings.scale_curve = shrinking_curve()
	var emitter := GPUParticles3D.new()
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.local_coords = false
	emitter.process_material = settings
	emitter.draw_pass_1 = particle_mesh
	emitter.material_override = particle_material
	emitter.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	return emitter


func shrinking_curve() -> CurveTexture:
	# Particulele se micșorează de la mărimea maximă la zero.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


## O explozie de particule. Refolosim emițătoarele create la pornire.
func burst(pos: Vector3, color: Color, amount: int = 20, speed: float = 7.0, size: float = 0.3, gravity: float = -9.0) -> void:
	var emitter := bursts[next_burst]
	next_burst = (next_burst + 1) % bursts.size()
	emitter.global_position = pos
	var settings := emitter.process_material as ParticleProcessMaterial
	settings.color = color
	settings.initial_velocity_min = speed * 0.5
	settings.initial_velocity_max = speed
	settings.scale_min = size * 0.6
	settings.scale_max = size * 1.4
	settings.gravity = Vector3(0, gravity, 0)
	emitter.amount_ratio = clampf(float(amount) / BURST_MAX_PARTICLES, 0.05, 1.0)
	emitter.restart()
	emitter.emitting = true


# =====================================================================
#  EFECTE PE ECRAN
# =====================================================================
func shake(amount: float) -> void:
	if GameState.settings["shake"]:
		trauma = minf(trauma + amount, 1.0)


func flash(color: Color, strength: float = 0.4) -> void:
	flash_rect.color = Color(color.r, color.g, color.b, strength)
	var tween := create_tween()
	tween.tween_property(flash_rect, "color:a", 0.0, 0.35)


## Text care urcă și dispare (ex: "+50").
func popup(pos: Vector3, text: String, color: Color, font_size: int = 64) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = font_size
	label.outline_size = 14
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # mereu cu fața spre cameră
	label.no_depth_test = true                          # se vede și prin obiecte
	label.pixel_size = 0.01
	scene.add_child(label)
	label.global_position = pos
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", pos + Vector3(0, 2.5, 0), 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


# =====================================================================
#  MATERIALE ȘI FORME
# =====================================================================
## Un material (culoare). emission = cât strălucește, alpha < 1 = transparent.
func mat(color: Color, emission: float = 0.0, metallic: float = 0.0, roughness: float = 0.7, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [color.to_html(), emission, metallic, roughness, alpha]
	if material_cache.has(key):
		return material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.metallic = metallic
	material.roughness = roughness
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_cache[key] = material
	return material


func box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func sphere_mesh(radius: float, segments: int = 14) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(segments / 2, 3)
	return mesh


## Cilindru (sau con, dacă una din raze e 0).
func cyl_mesh(top_radius: float, bottom_radius: float, height: float, segments: int = 14) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


## Inel (ca o gogoașă).
func torus_mesh(inner: float, outer: float, segments: int = 24) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = segments
	mesh.ring_segments = 8
	return mesh


func capsule_mesh(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 4
	return mesh


## Pune o formă în scenă, ca și copil al lui `parent`. Întoarce obiectul creat.
func add_mesh(parent: Node, mesh: Mesh, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scale_by := Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation = rot
	instance.scale = scale_by
	parent.add_child(instance)
	return instance


## Cer + soare pentru meniuri și ecrane. Întoarce Environment-ul.
func make_environment(parent: Node, sky_top: Color, horizon: Color, sun_color := Color.WHITE, sun_energy := 1.2) -> Environment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = horizon
	sky_material.ground_bottom_color = sky_top.darkened(0.5)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	if GameState.settings["low_graphics"]:
		env.glow_enabled = false   # LOW GRAPHICS: fără strălucire
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	parent.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.shadow_enabled = not GameState.settings["low_graphics"]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL   # mai rapid
	sun.rotation_degrees = Vector3(-45, -35, 0)
	parent.add_child(sun)
	return env


# =====================================================================
#  CLICK PE OBIECTE 3D
# =====================================================================
## Face un obiect 3D apăsabil cu mouse-ul (merge la orice mărime a ferestrei).
## Când dai click stânga pe el, se apelează `on_click`.
func make_clickable(target: Node3D, radius: float, on_click: Callable, offset := Vector3.ZERO) -> Area3D:
	target.get_viewport().physics_object_picking = true
	var area := Area3D.new()
	area.input_ray_pickable = true
	area.collision_layer = 1 << 7     # strat separat: nu atinge fizica jocului
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.position = offset
	var shape := SphereShape3D.new()
	shape.radius = radius
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	target.add_child(area)
	area.input_event.connect(on_click_area_input.bind(on_click))
	return area


func on_click_area_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int, on_click: Callable) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		on_click.call()


# =====================================================================
#  MĂȘTI CU FEȚE (broasca și boss-ul poartă fețele unor prieteni)
# =====================================================================
func load_texture_file(path: String) -> Texture2D:
	# Varianta normală: poza importată de Godot.
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture:
			return texture
	# Rezervă: poza a fost copiată, dar Godot încă n-a importat-o.
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func make_face_mask(texture: Texture2D, size: float, curve_radius: float) -> MeshInstance3D:
	# O poză cu fundal transparent, pusă pe o bucată de sferă (privește spre -Z).
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR   # marginea transparentă dispare
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED       # poza se vede la fel în orice lumină
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mask := MeshInstance3D.new()
	mask.mesh = curved_square_mesh(size, curve_radius, 10)
	mask.material_override = material
	mask.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mask


func curved_square_mesh(size: float, curve_radius: float, steps: int) -> ArrayMesh:
	# O grilă pătrată, îndoită ca o bucată de sferă: mijlocul iese în față (-Z),
	# marginile se duc puțin în spate, ca o mască pusă pe cap.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in steps + 1:
		for column in steps + 1:
			var u := float(column) / steps
			var v := float(row) / steps
			var x := (u - 0.5) * size
			var y := (0.5 - v) * size
			var back := curve_radius - sqrt(curve_radius * curve_radius - x * x - y * y)
			tool.set_normal(Vector3(x, y, -curve_radius + back).normalized())
			tool.set_uv(Vector2(u, v))
			tool.add_vertex(Vector3(x, y, back))
	for row in steps:
		for column in steps:
			var corner := row * (steps + 1) + column
			var below := corner + steps + 1
			tool.add_index(corner)
			tool.add_index(corner + 1)
			tool.add_index(below)
			tool.add_index(corner + 1)
			tool.add_index(below + 1)
			tool.add_index(below)
	return tool.commit()
