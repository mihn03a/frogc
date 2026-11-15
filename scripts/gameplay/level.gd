extends Node3D
## =====================================================================
##  LEVEL.GD - construiește și conduce un nivel
## =====================================================================
##  O singură scenă (level.tscn) construiește TOATE cele 5 niveluri din cod,
##  în funcție de GameState.current_level:
##    1 STEAGU, 2 BUNLOC       = lumea verde (vale, apă)
##    3 TRACTORUL, 4 CODLEA    = lumea de lavă (pietre care cad)
##    5 GHIMBAV                = lumea neon + arena boss-ului
##
##  Folosim un generator de numere aleatoare cu "seed" fix, deci fiecare
##  nivel arată la fel de fiecare dată când îl joci.
##
##  IMPORTANT: ordinea în care cerem numere de la `rng` contează!
##  Dacă o schimbi, se schimbă și forma nivelurilor.
## =====================================================================

const Player = preload("res://scripts/player/player.gd")
const Enemy = preload("res://scripts/gameplay/enemy.gd")
const Boss = preload("res://scripts/boss/boss.gd")
const ProjectilePool = preload("res://scripts/gameplay/projectile_pool.gd")
const HUD = preload("res://scripts/ui/hud.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")

const LEVEL_LENGTHS := [520.0, 640.0, 600.0, 720.0, 460.0]   # lungimea fiecărui nivel
const FLOOR_Y := -10.0                                          # înălțimea apei / lavei
const POWERUP_COLORS := {"shield": Color(0.3, 0.9, 1.0), "super": Color(1.0, 0.6, 0.1), "speed": Color(1.0, 0.25, 0.3), "magnet": Color(0.8, 0.35, 1.0)}
const POWERUP_LABELS := {"shield": "SHIELD", "super": "SUPER\nBOUNCE", "speed": "SPEED", "magnet": "MAGNET"}
const BROWN := Color(0.45, 0.28, 0.15)

# ---------------------------------------------------------------- variabile publice
var level := 1             # numărul nivelului (1..5)
var theme := "valley"      # "valley", "lava" sau "cyber"
var length := 500.0        # cât de lung e nivelul
var rng := RandomNumberGenerator.new()
var player
var pool                   # proiectilele refolosibile
var hud
var boss
var pal := {}              # paleta de culori a temei

# ---------------------------------------------------------------- variabile interne
var coins: Array[Area3D] = []
var pickups: Array[Area3D] = []
var falling_rocks: Array[Dictionary] = []   # {body, top, speed}
var moving_things: Array[Dictionary] = []   # platforme/mine/lasere care se mișcă
var clock := 0.0
var finished := false
var arena_center := Vector3.ZERO
var arena_started := false
var last_platform_x := 0.0   # poziția platformei anterioare:
var last_platform_y := 0.0   # ne asigurăm că următoarea e mereu accesibilă


# =====================================================================
#  PORNIRE
# =====================================================================
func _ready() -> void:
	level = GameState.current_level
	theme = GameState.LEVEL_THEMES[level - 1]
	length = LEVEL_LENGTHS[level - 1]
	rng.seed = 1000 + level * 7919
	choose_palette()
	create_sky_and_light()
	pool = ProjectilePool.new()
	add_child(pool)
	spawn_player()
	build_course()
	optimize_course()
	var first_decor_child := get_child_count()
	build_decor()
	optimize_decor(first_decor_child)
	create_hud_and_pause_menu()
	AudioManager.play_music(theme)
	show_level_title()


func optimize_course() -> void:
	# Performanță pe plăci video slabe: obiectele mici de pe traseu nu se mai
	# desenează când sunt departe, iar cele foarte mici nu aruncă umbre.
	for child in get_children():
		if child == player or child == pool or child == boss:
			continue
		optimize_meshes_in(child, 200.0)


func optimize_decor(first_child: int) -> void:
	# Decorul din fundal (nori, munți, clădiri) dispare abia de la 350 de unități.
	for i in range(first_child, get_child_count()):
		optimize_meshes_in(get_child(i), 350.0)


func optimize_meshes_in(node: Node, max_distance: float) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var size := mesh_instance.get_aabb().size.length()
		if size < 40.0:            # podeaua și pereții lungi rămân mereu vizibile
			mesh_instance.visibility_range_end = max_distance
		if size < 2.5:
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		optimize_meshes_in(child, max_distance)


func create_hud_and_pause_menu() -> void:
	hud = HUD.new()
	add_child(hud)
	hud.setup(player, length)
	add_child(PauseMenu.new())


func show_level_title() -> void:
	await get_tree().create_timer(0.4).timeout
	var title := "LEVEL %d: %s" % [level, GameState.LEVEL_NAMES[level - 1]]
	GameState.show_message.emit(title, Color(1.0, 0.95, 0.4))


# =====================================================================
#  CULORI, CER, LUMINĂ
# =====================================================================
func choose_palette() -> void:
	if theme == "valley":
		pal = {"sky": Color(0.22, 0.5, 0.95), "horizon": Color(0.75, 0.9, 1.0), "fog": Color(0.75, 0.88, 1.0),
			"sun": Color(1.0, 0.96, 0.85), "floor": Color(0.12, 0.42, 0.85), "floor_glow": 0.0,
			"top": Color(0.38, 0.82, 0.3), "side": Color(0.55, 0.36, 0.2), "accent": Color(1.0, 0.85, 0.2),
			"wall": Color(0.6, 1.0, 0.6), "fog_density": 0.0012}
	elif theme == "lava":
		pal = {"sky": Color(0.18, 0.03, 0.02), "horizon": Color(0.8, 0.3, 0.08), "fog": Color(0.45, 0.12, 0.04),
			"sun": Color(1.0, 0.6, 0.4), "floor": Color(0.9, 0.25, 0.02), "floor_glow": 0.8,
			"top": Color(0.2, 0.16, 0.16), "side": Color(0.12, 0.08, 0.08), "accent": Color(1.0, 0.45, 0.05),
			"wall": Color(1.0, 0.4, 0.1), "fog_density": 0.0035}
	else:
		pal = {"sky": Color(0.03, 0.02, 0.1), "horizon": Color(0.35, 0.08, 0.5), "fog": Color(0.2, 0.05, 0.35),
			"sun": Color(0.7, 0.8, 1.0), "floor": Color(0.04, 0.04, 0.09), "floor_glow": 0.0,
			"top": Color(0.1, 0.1, 0.18), "side": Color(0.06, 0.06, 0.1), "accent": Color(0.2, 1.0, 1.0),
			"wall": Color(1.0, 0.2, 0.9), "fog_density": 0.0025}


func create_sky_and_light() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = pal["sky"]
	sky_material.sky_horizon_color = pal["horizon"]
	sky_material.ground_horizon_color = pal["horizon"]
	sky_material.ground_bottom_color = (pal["sky"] as Color).darkened(0.4)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	if theme == "cyber":
		env.glow_intensity = 0.9     # neon-ul strălucește mai tare
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = pal["fog"]
	env.fog_density = pal["fog_density"]
	if GameState.settings["low_graphics"]:
		env.glow_enabled = false   # LOW GRAPHICS: fără strălucire
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_color = pal["sun"]
	sun.light_energy = 1.25
	sun.shadow_enabled = not GameState.settings["low_graphics"]   # LOW GRAPHICS: fără umbre
	sun.directional_shadow_max_distance = 80.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL   # o singură umbră: mai rapid
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)


# =====================================================================
#  JUCĂTORUL
# =====================================================================
func spawn_player() -> void:
	player = Player.new()
	player.position = Vector3(0, 6, 0)
	add_child(player)
	player.velocity = Vector3(0, 6, -15)
	player.bounced_on.connect(on_player_bounced_on)
	player.died.connect(on_player_died)
	add_floating_particles()


func on_player_died() -> void:
	hud.visible = false


func add_floating_particles() -> void:
	# Particule care plutesc în jurul broaștei (polen / scântei / pixeli).
	var particles: GPUParticles3D
	if theme == "valley":
		particles = FX.make_emitter(Color(1.0, 1.0, 0.8), 40, 4.0, Vector3.UP, 180.0, 0.2, 0.6, Vector3.ZERO, 0.12, Vector3(25, 12, 30))
	elif theme == "lava":
		particles = FX.make_emitter(Color(1.0, 0.5, 0.1), 90, 3.0, Vector3.UP, 30.0, 1.0, 3.0, Vector3(0, 1, 0), 0.18, Vector3(30, 10, 40))
	else:
		particles = FX.make_emitter(Color(0.3, 1.0, 1.0), 70, 2.5, Vector3.UP, 180.0, 0.3, 1.0, Vector3.ZERO, 0.1, Vector3(30, 14, 40))
	particles.position = Vector3(0, 0, -20)
	player.add_child(particles)
	particles.emitting = true


# =====================================================================
#  FUNCȚII AJUTĂTOARE PENTRU OBIECTE CU COLIZIUNE
# =====================================================================
func make_body(pos: Vector3, kind: String, movable: bool) -> PhysicsBody3D:
	# Corp static (nu se mișcă) sau animat (îl mișcăm noi din cod).
	var body: PhysicsBody3D
	if movable:
		var animated := AnimatableBody3D.new()
		animated.sync_to_physics = false
		body = animated
	else:
		body = StaticBody3D.new()
	body.position = pos
	body.set_meta("kind", kind)   # eticheta citită de player.gd la coliziune
	return body


func add_shape(body: Node3D, shape: Shape3D, offset: Vector3 = Vector3.ZERO) -> void:
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = offset
	body.add_child(collision)


func box_shape(size: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape


func sphere_shape(radius: float) -> SphereShape3D:
	var shape := SphereShape3D.new()
	shape.radius = radius
	return shape


func cylinder_shape(radius: float, height: float) -> CylinderShape3D:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	return shape


func make_box(pos: Vector3, size: Vector3, material: Material, kind := "solid", movable := false) -> PhysicsBody3D:
	var body := make_body(pos, kind, movable)
	add_shape(body, box_shape(size))
	FX.add_mesh(body, FX.box_mesh(size), material)
	add_child(body)
	return body


func make_cylinder(pos: Vector3, radius: float, height: float, material: Material, kind := "solid", movable := false, segments := 14) -> PhysicsBody3D:
	var body := make_body(pos, kind, movable)
	add_shape(body, cylinder_shape(radius, height))
	FX.add_mesh(body, FX.cyl_mesh(radius, radius, height, segments), material)
	add_child(body)
	return body


func make_trigger(pos: Vector3, shape: Shape3D) -> Area3D:
	# Zonă invizibilă care detectează doar jucătorul (stratul 2).
	var area := Area3D.new()
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	add_shape(area, shape)
	return area


func add_mover(body: Node3D, origin: Vector3, axis: Vector3, amount: float, speed: float, phase: float, spin: float, swing: bool = false) -> void:
	# Obiect care se mișcă înainte-înapoi (sinus) pe o axă, se rotește sau se balansează.
	moving_things.append({"body": body, "origin": origin, "axis": axis, "amount": amount,
		"speed": speed, "phase": phase, "spin": spin, "swing": swing})


func random_side_x(min_dist: float, max_dist: float) -> float:
	# O poziție X la stânga SAU la dreapta traseului.
	var dist := rng.randf_range(min_dist, max_dist)
	if rng.randf() < 0.5:
		return dist
	return -dist


# =====================================================================
#  TRASEUL
# =====================================================================
func build_course() -> void:
	build_floor_and_walls()
	build_start_platform()
	var powerup_order := shuffled_powerups()
	var powerup_spots := [0.15, 0.37, 0.6, 0.82]   # la ce procent din nivel apar
	var next_powerup := 0
	var z := -26.0
	var end_z := -length + 25.0
	while z > end_z:
		var progress := -z / length
		if next_powerup < 4 and progress >= powerup_spots[next_powerup]:
			var px := rng.randf_range(-6, 6)
			var py := rng.randf_range(4, 8)
			create_powerup(Vector3(px, py, z + 6.0), powerup_order[next_powerup])
			next_powerup += 1
		build_segment(z)
		z -= rng.randf_range(14.0, 18.0) + level * 0.6   # distanța până la următoarea bucată
	if level < 5:
		build_finish_gate(Vector3(0, 5, -length))
	else:
		build_boss_arena()


func build_floor_and_walls() -> void:
	# Podeaua: apă / lavă / grilă. Te rănește și te aruncă înapoi la ultima platformă.
	var shine := 0.0
	if theme == "valley":
		shine = 0.2
	var floor_material := FX.mat(pal["floor"], pal["floor_glow"], shine, 0.15)
	make_box(Vector3(0, FLOOR_Y - 1.0, -length / 2.0), Vector3(400, 2, length + 400), floor_material, "floor_hazard")
	# Pereți laterali transparenți: broasca ricoșează din ei
	var wall_material := FX.mat(pal["wall"], 0.0, 0.0, 0.5, 0.03)
	for side in [-1.0, 1.0]:
		make_box(Vector3(side * 16.5, 15, -length / 2.0), Vector3(1, 60, length + 80), wall_material, "wall")
		for i in int(length / 40.0):
			FX.add_mesh(self, FX.box_mesh(Vector3(0.3, 0.3, 10)), FX.mat(pal["wall"], 3.0), Vector3(side * 16.2, FLOOR_Y + 1.0, -i * 40.0))


func build_start_platform() -> void:
	make_box(Vector3(0, 0, 4), Vector3(14, 2, 18), FX.mat(pal["top"]), "solid")
	make_box(Vector3(0, -2.5, 4), Vector3(12, 3, 16), FX.mat(pal["side"]), "solid")


func shuffled_powerups() -> Array:
	# Amestecăm cele 4 power-up-uri (algoritmul Fisher-Yates).
	var list := ["shield", "super", "speed", "magnet"]
	for i in range(3, 0, -1):
		var j := rng.randi_range(0, i)
		var temp = list[i]
		list[i] = list[j]
		list[j] = temp
	return list


func build_segment(z: float) -> void:
	# O "bucată" de traseu = ceva pe care sari + monede + un obstacol.
	# Traseu corect: următoarea platformă e max 6 unități în lateral și
	# max 1,5 unități mai sus decât precedenta (se poate ajunge cu o săritură normală).
	var x := clampf(last_platform_x + rng.randf_range(-6.0, 6.0), -9.0, 9.0)
	var y := clampf(last_platform_y + rng.randf_range(-3.0, 1.5), -3.0, 3.0)
	last_platform_x = x
	last_platform_y = y
	# 1) suport: platformă sau trambulină
	if rng.randf() < 0.18:
		create_jump_pad(Vector3(x, y, z))
	else:
		var radius := rng.randf_range(3.6, 5.4) - level * 0.2   # platforme mai mici în nivelurile grele
		create_platform(Vector3(x, y, z), radius)
	# 2) recompensă: un arc de monede deasupra
	create_coin_arc(Vector3(x, y + 3.0, z + 8.0), Vector3(x, y + 3.0, z - 8.0), 5, 4.0)
	# 3) obstacol, în funcție de temă
	var chance := rng.randf()
	var enemy_x := rng.randf_range(-9.0, 9.0)
	var enemy_y := rng.randf_range(3.0, 8.0)
	var enemy_pos := Vector3(enemy_x, enemy_y, z - 8.0)
	var mine_pos := Vector3(enemy_x, enemy_y, z - 9.0)
	if theme == "valley":
		add_valley_obstacle(chance, z, enemy_pos, mine_pos)
	elif theme == "lava":
		add_lava_obstacle(chance, z, enemy_pos, mine_pos)
	else:
		add_cyber_obstacle(chance, z, enemy_pos, mine_pos)


func add_valley_obstacle(chance: float, z: float, enemy_pos: Vector3, mine_pos: Vector3) -> void:
	if chance < 0.25:
		var tx := rng.randf_range(-13.0, 13.0)
		var tz := z + rng.randf_range(-6.0, 6.0)
		create_tree(Vector3(tx, 0, tz))
	elif chance < 0.5 + level * 0.06:
		var type := "fly"
		if level == 2 and rng.randf() < 0.5:
			type = "hornet"
		create_enemy(enemy_pos, type)
	elif level == 2 and chance < 0.8:
		create_mine(mine_pos)
	elif chance < 0.85:
		create_tree(Vector3(rng.randf_range(-13.0, 13.0), 0, z - 9.0))


func add_lava_obstacle(chance: float, z: float, enemy_pos: Vector3, mine_pos: Vector3) -> void:
	if chance < 0.25:
		create_falling_rock(Vector3(rng.randf_range(-9.0, 9.0), 0, z - 6.0))
	elif chance < 0.52:
		create_enemy(enemy_pos, "bat")
	elif chance < 0.66:
		create_spire(Vector3(rng.randf_range(-13.0, 13.0), 0, z - 5.0))
	elif level == 4 and chance < 0.85:
		create_mine(mine_pos)
		create_falling_rock(Vector3(rng.randf_range(-9.0, 9.0), 0, z - 12.0))


func add_cyber_obstacle(chance: float, z: float, enemy_pos: Vector3, mine_pos: Vector3) -> void:
	if chance < 0.22:
		create_laser_gate(z - 9.0)
	elif chance < 0.47:
		create_enemy(enemy_pos, "drone")
	elif chance < 0.62:
		create_hammer(Vector3(rng.randf_range(-6.0, 6.0), 0, z - 9.0))
	elif chance < 0.75:
		create_pylon(Vector3(rng.randf_range(-13.0, 13.0), 0, z - 5.0))
	elif chance < 0.88:
		create_mine(mine_pos)


# =====================================================================
#  PLATFORME
# =====================================================================
func create_platform(pos: Vector3, radius: float) -> void:
	if theme == "valley":
		create_grass_platform(pos, radius)
	elif theme == "lava":
		create_lava_platform(pos, radius)
	else:
		create_neon_platform(pos, radius)


func create_grass_platform(pos: Vector3, r: float) -> void:
	var body := make_cylinder(pos, r, 1.2, FX.mat(pal["top"]), "solid")
	FX.add_mesh(body, FX.cyl_mesh(r * 0.95, 0.3, r * 1.5, 10), FX.mat(pal["side"]), Vector3(0, -0.6 - r * 0.75, 0))
	if r > 4.0:
		create_small_tree(body, Vector3(r * 0.5, 0.6, 0))
	for i in 3:   # câteva flori
		var angle := rng.randf() * TAU
		var flower_color := Color(1, rng.randf_range(0.3, 1.0), 0.6)
		FX.add_mesh(body, FX.sphere_mesh(0.18, 6), FX.mat(flower_color), Vector3(cos(angle) * r * 0.7, 0.65, sin(angle) * r * 0.7))


func create_lava_platform(pos: Vector3, r: float) -> void:
	# Unele platforme sunt instabile: se prăbușesc după ce sari pe ele.
	var unstable_chance := 0.5
	if level == 3:
		unstable_chance = 0.35
	var unstable := rng.randf() < unstable_chance
	var kind := "solid"
	var glow := Color(1.0, 0.5, 0.1)
	if unstable:
		kind = "unstable"
		glow = Color(1.0, 0.2, 0.05)
	var body := make_cylinder(pos, r, 1.4, FX.mat(pal["top"], 0.0, 0.0, 0.9), kind, unstable, 6)
	FX.add_mesh(body, FX.torus_mesh(r * 0.85, r * 0.92, 6), FX.mat(glow, 3.0), Vector3(0, 0.72, 0))
	FX.add_mesh(body, FX.cyl_mesh(r * 0.9, 0.2, r * 1.3, 6), FX.mat(pal["side"]), Vector3(0, -0.7 - r * 0.65, 0))
	if unstable:   # o "crăpătură" care strălucește
		FX.add_mesh(body, FX.box_mesh(Vector3(r * 1.6, 0.05, 0.15)), FX.mat(glow, 4.0), Vector3(0, 0.72, 0), Vector3(0, 0.6, 0))


func create_neon_platform(pos: Vector3, r: float) -> void:
	var moving := rng.randf() < 0.4
	var body := make_cylinder(pos, r, 1.0, FX.mat(pal["top"], 0.0, 0.8, 0.3), "solid", moving, 6)
	var neon: Color = pal["wall"]
	if rng.randf() < 0.5:
		neon = pal["accent"]
	FX.add_mesh(body, FX.torus_mesh(r * 0.95, r * 1.02, 6), FX.mat(neon, 4.0), Vector3(0, 0.5, 0))
	FX.add_mesh(body, FX.cyl_mesh(r * 0.3, r * 0.3, 0.05, 6), FX.mat(neon, 2.0), Vector3(0, 0.52, 0))
	if moving:   # se mișcă stânga-dreapta
		var amount := rng.randf_range(3.0, 5.0)
		var speed := rng.randf_range(1.0, 1.8)
		var phase := rng.randf() * TAU
		add_mover(body, pos, Vector3.RIGHT, amount, speed, phase, 0.0)


func create_jump_pad(pos: Vector3) -> void:
	# Trambulina roz: te aruncă foarte sus.
	var base := make_cylinder(pos, 2.6, 1.0, FX.mat(pal["top"]), "solid")
	var pad := make_cylinder(pos + Vector3(0, 0.75, 0), 2.0, 0.5, FX.mat(Color(1.0, 0.3, 0.6), 1.5), "pad")
	FX.add_mesh(pad, FX.torus_mesh(1.6, 1.9, 20), FX.mat(Color(1.0, 0.95, 0.3), 3.0), Vector3(0, 0.3, 0))
	FX.add_mesh(base, FX.cyl_mesh(2.4, 0.3, 3.0, 10), FX.mat(pal["side"]), Vector3(0, -2.0, 0))


# =====================================================================
#  OBSTACOLE
# =====================================================================
func create_tree(pos: Vector3) -> void:
	# Copac înalt care iese din lac: ricoșezi din el ca la pinball.
	var height := rng.randf_range(10.0, 17.0)
	var body := make_body(Vector3(pos.x, FLOOR_Y, pos.z), "bumper", false)
	add_shape(body, cylinder_shape(0.9, height), Vector3(0, height / 2.0, 0))
	add_shape(body, sphere_shape(2.6), Vector3(0, height + 1.5, 0))
	FX.add_mesh(body, FX.cyl_mesh(0.7, 1.0, height, 8), FX.mat(BROWN), Vector3(0, height / 2.0, 0))
	var leaves := FX.mat(Color(0.2, rng.randf_range(0.55, 0.75), 0.2))
	FX.add_mesh(body, FX.sphere_mesh(2.6, 10), leaves, Vector3(0, height + 1.5, 0))
	FX.add_mesh(body, FX.sphere_mesh(1.8, 8), leaves, Vector3(1.5, height + 0.6, 0.6))
	FX.add_mesh(body, FX.sphere_mesh(1.7, 8), leaves, Vector3(-1.4, height + 0.9, -0.5))
	add_child(body)


func create_small_tree(parent: Node3D, pos: Vector3) -> void:
	# Doar decor (fără coliziune), pus pe platformele mari.
	FX.add_mesh(parent, FX.cyl_mesh(0.2, 0.3, 2.0, 6), FX.mat(BROWN), pos + Vector3(0, 1.0, 0))
	FX.add_mesh(parent, FX.sphere_mesh(1.0, 8), FX.mat(Color(0.25, 0.7, 0.25)), pos + Vector3(0, 2.4, 0))


func create_spire(pos: Vector3) -> void:
	# Turn de rocă vulcanică (lumea de lavă).
	var height := rng.randf_range(12.0, 20.0)
	var body := make_body(Vector3(pos.x, FLOOR_Y, pos.z), "bumper", false)
	add_shape(body, cylinder_shape(1.3, height), Vector3(0, height / 2.0, 0))
	FX.add_mesh(body, FX.cyl_mesh(0.3, 2.2, height, 6), FX.mat(Color(0.25, 0.12, 0.08), 0.0, 0.0, 0.95), Vector3(0, height / 2.0, 0))
	FX.add_mesh(body, FX.cyl_mesh(0.35, 0.6, 1.0, 6), FX.mat(Color(1.0, 0.4, 0.05), 4.0), Vector3(0, height, 0))
	add_child(body)


func create_pylon(pos: Vector3) -> void:
	# Stâlp cu dungi de neon (lumea cyber).
	var height := rng.randf_range(12.0, 22.0)
	var body := make_box(Vector3(pos.x, FLOOR_Y + height / 2.0, pos.z), Vector3(2.0, height, 2.0), FX.mat(Color(0.12, 0.12, 0.2), 0.0, 0.9, 0.3), "bumper")
	for i in int(height / 3.0):
		var stripe: Color = pal["wall"]
		if i % 2 == 0:
			stripe = pal["accent"]
		FX.add_mesh(body, FX.box_mesh(Vector3(2.1, 0.15, 2.1)), FX.mat(stripe, 4.0), Vector3(0, -height / 2.0 + 1.5 + i * 3.0, 0))


func create_mine(pos: Vector3) -> void:
	# Mină cu țepi care plutește în sus și în jos. Atingerea = damage.
	var body := make_body(pos, "hazard", true)
	body.set_meta("damage", 15.0)
	add_shape(body, sphere_shape(1.3))
	var core_color := Color(1.0, 0.15, 0.1)
	if theme == "cyber":
		core_color = Color(1.0, 0.1, 0.6)
	FX.add_mesh(body, FX.sphere_mesh(1.0, 10), FX.mat(Color(0.15, 0.15, 0.17), 0.0, 0.7, 0.4))
	FX.add_mesh(body, FX.sphere_mesh(0.45, 8), FX.mat(core_color, 4.0), Vector3(0, 0, 0.75))
	add_mine_spikes(body)
	add_child(body)
	add_mover(body, pos, Vector3.UP, 1.0, 2.0, rng.randf() * TAU, 1.5)


func add_mine_spikes(body: Node3D) -> void:
	# 6 țepi: [direcția, rotația care întoarce conul în acea direcție]
	var spikes := [
		[Vector3.UP, Vector3.ZERO], [Vector3.DOWN, Vector3(PI, 0, 0)],
		[Vector3.LEFT, Vector3(0, 0, PI / 2)], [Vector3.RIGHT, Vector3(0, 0, -PI / 2)],
		[Vector3.FORWARD, Vector3(-PI / 2, 0, 0)], [Vector3.BACK, Vector3(PI / 2, 0, 0)],
	]
	var spike_material := FX.mat(Color(0.7, 0.7, 0.75), 0.0, 0.9, 0.3)
	for spike in spikes:
		var direction: Vector3 = spike[0]
		var rotation_angles: Vector3 = spike[1]
		FX.add_mesh(body, FX.cyl_mesh(0.0, 0.25, 0.9, 6), spike_material, direction * 1.1, rotation_angles)


func create_falling_rock(pos: Vector3) -> void:
	# Piatră de foc care cade din cer când te apropii, apoi o ia de la capăt.
	var body := make_body(Vector3.ZERO, "hazard", true)
	body.set_meta("damage", 18.0)
	var top := 45.0 + rng.randf_range(0.0, 10.0)
	body.position = Vector3(pos.x, top, pos.z)
	add_shape(body, sphere_shape(1.6))
	FX.add_mesh(body, FX.sphere_mesh(1.7, 6), FX.mat(Color(0.3, 0.12, 0.08), 0.0, 0.0, 1.0))
	FX.add_mesh(body, FX.sphere_mesh(1.2, 5), FX.mat(Color(1.0, 0.4, 0.05), 3.0), Vector3(0.6, 0.4, 0.5))
	var fire_trail := FX.make_emitter(Color(1.0, 0.45, 0.1), 30, 0.8, Vector3.UP, 20.0, 1.0, 3.0, Vector3.ZERO, 0.4)
	body.add_child(fire_trail)
	fire_trail.emitting = true
	add_child(body)
	falling_rocks.append({"body": body, "top": top, "speed": rng.randf_range(16.0, 24.0)})


func create_laser_gate(z: float) -> void:
	# Doi stâlpi și o rază laser care urcă și coboară între ei.
	var post_material := FX.mat(Color(0.15, 0.15, 0.22), 0.0, 0.9, 0.3)
	for side in [-1.0, 1.0]:
		var post := make_box(Vector3(side * 15.0, 5, z), Vector3(1.2, 30, 1.2), post_material, "bumper")
		FX.add_mesh(post, FX.box_mesh(Vector3(1.3, 30, 0.2)), FX.mat(Color(1.0, 0.1, 0.3), 2.0), Vector3(0, 0, 0.6))
	var beam := make_box(Vector3(0, 3, z), Vector3(29, 0.5, 0.5), FX.mat(Color(1.0, 0.1, 0.25), 6.0), "hazard", true)
	beam.set_meta("damage", 15.0)
	var speed := rng.randf_range(1.2, 2.0)
	var phase := rng.randf() * TAU
	add_mover(beam, Vector3(0, 3, z), Vector3.UP, 6.0, speed, phase, 0.0)


func create_hammer(pos: Vector3) -> void:
	# Ciocan mecanic care se balansează: nu rănește, dar te împinge.
	var pivot := Vector3(pos.x, 18.0, pos.z)
	FX.add_mesh(self, FX.box_mesh(Vector3(3, 1, 3)), FX.mat(Color(0.2, 0.2, 0.28), 0.0, 0.9, 0.3), pivot)
	var body := make_body(pivot, "bumper", true)
	add_shape(body, box_shape(Vector3(3.2, 3.2, 3.2)), Vector3(0, -14, 0))
	FX.add_mesh(body, FX.box_mesh(Vector3(0.6, 12, 0.6)), FX.mat(Color(0.5, 0.52, 0.6), 0.0, 0.9, 0.3), Vector3(0, -6, 0))
	FX.add_mesh(body, FX.box_mesh(Vector3(3.2, 3.2, 3.2)), FX.mat(Color(0.18, 0.18, 0.25), 0.0, 0.9, 0.3), Vector3(0, -14, 0))
	FX.add_mesh(body, FX.box_mesh(Vector3(3.3, 0.3, 3.3)), FX.mat(pal["wall"], 4.0), Vector3(0, -14, 0))
	add_child(body)
	var speed := rng.randf_range(1.2, 1.8)
	var phase := rng.randf() * TAU
	add_mover(body, pivot, Vector3.ZERO, 1.1, speed, phase, 0.0, true)


func create_enemy(pos: Vector3, type: String) -> void:
	var enemy := Enemy.new()
	enemy.setup(type, player, pool)
	enemy.position = pos
	add_child(enemy)


# =====================================================================
#  MONEDE ȘI POWER-UP-URI
# =====================================================================
func create_coin(pos: Vector3) -> void:
	var coin := make_trigger(pos, sphere_shape(0.9))
	var flat := Vector3(PI / 2, 0, 0)   # culcăm cilindrul ca să arate ca o monedă
	FX.add_mesh(coin, FX.cyl_mesh(0.55, 0.55, 0.14, 14), FX.mat(Color(1.0, 0.82, 0.15), 0.6, 0.9, 0.3), Vector3.ZERO, flat)
	FX.add_mesh(coin, FX.cyl_mesh(0.3, 0.3, 0.16, 10), FX.mat(Color(0.4, 0.85, 0.3), 0.5), Vector3.ZERO, flat)
	add_child(coin)
	coin.body_entered.connect(on_coin_touched.bind(coin))
	coins.append(coin)


func create_coin_arc(from: Vector3, to: Vector3, count: int, height: float) -> void:
	for i in count:
		var t := float(i) / maxf(count - 1, 1)   # 0 la început, 1 la final
		var pos := from.lerp(to, t)
		pos.y += sin(t * PI) * height            # forma de arc
		create_coin(pos)


func on_coin_touched(body: Node3D, coin: Area3D) -> void:
	if not body.is_in_group("player") or not is_instance_valid(coin) or coin.has_meta("taken"):
		return
	coin.set_meta("taken", true)
	var points := GameState.add_score(25)
	if randf() < 0.25:
		GameState.add_evo(1)
	AudioManager.play("collect", 1.0 + randf() * 0.2)
	FX.burst(coin.global_position, Color(1.0, 0.85, 0.2), 10, 4.0, 0.2)
	FX.popup(coin.global_position, "+%d" % points, Color(1.0, 0.9, 0.3), 40)
	coins.erase(coin)
	coin.queue_free()


func create_powerup(pos: Vector3, kind: String) -> void:
	var item := make_trigger(pos, sphere_shape(1.5))
	item.set_meta("kind", kind)
	var color: Color = POWERUP_COLORS[kind]
	FX.add_mesh(item, FX.sphere_mesh(0.7, 12), FX.mat(color, 3.0))
	FX.add_mesh(item, FX.sphere_mesh(1.3, 16), FX.mat(color.lightened(0.4), 0.8, 0.0, 0.1, 0.3))
	FX.add_mesh(item, FX.torus_mesh(1.4, 1.55, 24), FX.mat(Color.WHITE, 2.0), Vector3.ZERO, Vector3(PI / 2, 0, 0))
	var label := make_label(POWERUP_LABELS[kind], 72, 16, color.lightened(0.3), 0.01)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # mereu cu fața spre cameră
	label.position = Vector3(0, 2.3, 0)
	item.add_child(label)
	add_child(item)
	item.body_entered.connect(on_powerup_touched.bind(item))
	pickups.append(item)


func on_powerup_touched(body: Node3D, item: Area3D) -> void:
	if not body.is_in_group("player") or not is_instance_valid(item) or item.has_meta("taken"):
		return
	item.set_meta("taken", true)
	body.call("activate_powerup", str(item.get_meta("kind")))
	GameState.add_score(100)
	pickups.erase(item)
	item.queue_free()


func make_label(text: String, font_size: int, outline: int, color: Color, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.outline_size = outline
	label.modulate = color
	label.pixel_size = pixel_size
	return label


# =====================================================================
#  FINALUL NIVELULUI
# =====================================================================
func build_finish_gate(pos: Vector3) -> void:
	var gate := Node3D.new()
	gate.position = pos
	add_child(gate)
	var standing := Vector3(PI / 2, 0, 0)   # inelele stau în picioare
	FX.add_mesh(gate, FX.torus_mesh(7.0, 8.0, 40), FX.mat(Color(1.0, 0.85, 0.2), 2.5, 0.8, 0.3), Vector3.ZERO, standing)
	FX.add_mesh(gate, FX.torus_mesh(5.5, 6.0, 40), FX.mat(Color(0.4, 1.0, 0.4), 3.0, 0, 0.5, 0.6), Vector3.ZERO, standing)
	var label := make_label("FINISH", 200, 30, Color(1.0, 0.95, 0.4), 0.02)
	label.position = Vector3(0, 10.5, 0)
	gate.add_child(label)
	make_box(pos + Vector3(0, -8, -12), Vector3(20, 2, 20), FX.mat(pal["top"]), "solid")
	# zona invizibilă: când broasca trece prin ea, nivelul e gata
	var finish_zone := make_trigger(Vector3.ZERO, box_shape(Vector3(34, 60, 3)))
	gate.add_child(finish_zone)
	finish_zone.body_entered.connect(on_finish_reached)


func on_finish_reached(body: Node3D) -> void:
	if finished or not body.is_in_group("player"):
		return
	finished = true
	player.call("start_cinematic")
	AudioManager.play("level_complete")
	GameState.show_message.emit("LEVEL COMPLETE!  +%d" % (1000 * level), Color(0.5, 1.0, 0.5))
	FX.flash(Color(1, 1, 0.6), 0.4)
	for i in 4:   # artificii
		var offset := Vector3(randf_range(-4, 4), randf_range(0, 4), randf_range(-6, 0))
		FX.burst(player.global_position + offset, Color(randf(), 1.0, 0.4), 32, 12.0, 0.4)
	await get_tree().create_timer(2.2).timeout
	GameState.complete_level()


# =====================================================================
#  ARENA BOSS-ULUI (doar nivelul 5)
# =====================================================================
func build_boss_arena() -> void:
	var c := Vector3(0, 0, -length - 15.0)
	arena_center = c
	# podeaua rotundă și "stânca" de sub ea
	make_cylinder(c + Vector3(0, -1, 0), 25.0, 2.0, FX.mat(Color(0.08, 0.08, 0.14), 0.0, 0.9, 0.3), "solid", false, 32)
	FX.add_mesh(self, FX.cyl_mesh(25.5, 4.0, 14.0, 16), FX.mat(Color(0.05, 0.05, 0.09), 0.0, 0.8, 0.4), c + Vector3(0, -9, 0))
	for r in [8.0, 16.0, 24.0]:   # cercuri de neon pe podea
		FX.add_mesh(self, FX.torus_mesh(r - 0.15, r + 0.15, 48), FX.mat(pal["accent"], 4.0), c + Vector3(0, 0.02, 0))
	create_arena_pads(c)
	var label := make_label("BOSS ARENA", 220, 30, Color(1.0, 0.3, 0.8), 0.03)
	label.position = c + Vector3(0, 22, -26)
	add_child(label)
	# Zona care pornește lupta - doar DEASUPRA podelei (y 0..40),
	# ca să nu pornească dacă broasca e sub arenă.
	var entry_zone := make_trigger(c + Vector3(0, 20, 0), cylinder_shape(19.0, 40.0))
	add_child(entry_zone)
	entry_zone.body_entered.connect(on_arena_entered)
	boss = Boss.new()
	boss.setup(player, pool, c)
	add_child(boss)
	boss.defeated.connect(on_boss_defeated)


func create_arena_pads(c: Vector3) -> void:
	# 4 trambuline în jurul boss-ului
	for i in 4:
		var angle := i * TAU / 4.0 + PI / 4.0
		var pos := c + Vector3(cos(angle) * 15.0, 0.2, sin(angle) * 15.0)
		var pad := make_cylinder(pos, 2.4, 0.5, FX.mat(Color(1.0, 0.3, 0.6), 2.0), "pad")
		FX.add_mesh(pad, FX.torus_mesh(2.0, 2.3, 24), FX.mat(Color(1.0, 0.95, 0.3), 4.0), Vector3(0, 0.3, 0))


func on_arena_entered(body: Node3D) -> void:
	if arena_started or not body.is_in_group("player"):
		return
	arena_started = true
	# call_deferred: nu putem adăuga corpuri fizice chiar în timpul unui semnal fizic
	call_deferred("start_boss_fight")


func start_boss_fight() -> void:
	raise_arena_walls()
	player.call("enter_arena", arena_center, boss)
	boss.start_fight()
	hud.show_boss_bar(true)
	GameState.show_message.emit("THE BIG NIC APPEARS!", Color(1.0, 0.4, 0.8))
	FX.shake(0.6)


func raise_arena_walls() -> void:
	# 24 de pereți în cerc. Sunt solizi imediat; doar aspectul lor "urcă" din pământ.
	var wall_material := FX.mat(Color(1.0, 0.2, 0.9), 0.5, 0.0, 0.5, 0.08)
	for i in 24:
		var angle := i * TAU / 24.0
		var pos := arena_center + Vector3(cos(angle) * 26.0, 19.0, sin(angle) * 26.0)
		var wall := make_box(pos, Vector3(7.2, 40, 1.2), wall_material, "wall")
		wall.rotation.y = PI / 2.0 - angle
		for child in wall.get_children():
			if child is MeshInstance3D:
				animate_rise(child as MeshInstance3D)


func animate_rise(mesh: MeshInstance3D) -> void:
	mesh.position.y = -45.0
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "position:y", 0.0, 1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func on_boss_defeated() -> void:
	player.call("start_cinematic")
	await get_tree().create_timer(1.5).timeout
	GameState.go_victory()


# =====================================================================
#  ÎN FIECARE CADRU
# =====================================================================
func _physics_process(delta: float) -> void:
	clock += delta
	if player == null:
		return
	keep_player_out_of_arena_basement()
	var player_pos: Vector3 = player.global_position
	update_coins(delta, player_pos)
	update_powerup_items(delta)
	update_moving_things(delta)
	update_falling_rocks(delta, player_pos)


func keep_player_out_of_arena_basement() -> void:
	# Plasă de siguranță: broasca nu are voie să ajungă sub arena boss-ului.
	if level != 5:
		return
	var pos: Vector3 = player.global_position
	if pos.z >= arena_center.z + 24.0 or pos.y >= -0.5:
		return
	var flat_distance := Vector2(pos.x - arena_center.x, pos.z - arena_center.z).length()
	if flat_distance < 26.0 or not arena_started:
		player.global_position = arena_center + Vector3(0, 5, 12)
		player.velocity = Vector3(0, 14, -4)
		FX.burst(player.global_position, Color(0.3, 1.0, 1.0), 30, 10.0, 0.4)


func update_coins(delta: float, player_pos: Vector3) -> void:
	var magnet: bool = player.powerups["magnet"] > 0.0
	for coin in coins:
		if not is_instance_valid(coin):
			continue
		if absf(coin.position.z - player_pos.z) > 60.0:
			continue   # prea departe: nu ne ocupăm de ea (economisim performanță)
		coin.rotate_y(delta * 3.0)
		if magnet:
			pull_coin_to_player(coin, player_pos, delta)


func pull_coin_to_player(coin: Area3D, player_pos: Vector3, delta: float) -> void:
	var to_player := player_pos - coin.global_position
	var distance := to_player.length()
	if distance < 14.0:
		coin.global_position += to_player.normalized() * minf(32.0 * delta, distance)


func update_powerup_items(delta: float) -> void:
	for item in pickups:
		if is_instance_valid(item):
			item.rotate_y(delta * 1.5)
			item.position.y += sin(clock * 3.0) * 0.01   # plutește ușor


func update_moving_things(delta: float) -> void:
	for thing in moving_things:
		var body: Node3D = thing["body"]
		if not is_instance_valid(body):
			continue
		var wave := sin(clock * float(thing["speed"]) + float(thing["phase"]))   # între -1 și 1
		if thing["swing"]:
			body.rotation.z = wave * float(thing["amount"])     # balans (ciocanul)
		else:
			var origin: Vector3 = thing["origin"]
			var axis: Vector3 = thing["axis"]
			body.position = origin + axis * wave * float(thing["amount"])
		if float(thing["spin"]) != 0.0:
			body.rotate_y(delta * float(thing["spin"]))


func update_falling_rocks(delta: float, player_pos: Vector3) -> void:
	for rock in falling_rocks:
		var body: Node3D = rock["body"]
		var top: float = rock["top"]
		var distance_ahead := player_pos.z - body.position.z
		var player_is_near := distance_ahead > -10.0 and distance_ahead < 75.0
		var already_falling := body.position.y < top - 1.0
		if player_is_near or already_falling:
			body.position.y -= float(rock["speed"]) * delta
			body.rotate_x(delta * 2.0)
			if body.position.y < FLOOR_Y - 2.0:
				# a ajuns în lavă: stropi, apoi o urcăm înapoi sus
				FX.burst(Vector3(body.position.x, FLOOR_Y, body.position.z), Color(1.0, 0.5, 0.1), 20, 8.0, 0.4)
				body.position.y = top


# =====================================================================
#  REACȚII LA SĂRITURILE BROAȘTEI
# =====================================================================
func on_player_bounced_on(body) -> void:
	if body == null or not is_instance_valid(body):
		return
	var kind := str(body.get_meta("kind", "solid"))
	if kind == "unstable":
		collapse_platform(body)
	elif kind == "bumper":
		GameState.add_score(25)
		wobble_first_mesh(body)


func wobble_first_mesh(body: Node3D) -> void:
	# Obiectul se umflă puțin și revine (feedback vizual).
	for child in body.get_children():
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			var normal_scale := mesh.scale
			var tween := mesh.create_tween()
			tween.tween_property(mesh, "scale", normal_scale * 1.15, 0.06)
			tween.tween_property(mesh, "scale", normal_scale, 0.15)
			return


func collapse_platform(body: Node3D) -> void:
	# Platforma instabilă: tremură, cade, apoi după 3 secunde revine.
	if body.has_meta("collapsing"):
		return
	body.set_meta("collapsing", true)
	var origin := body.position
	var tween := body.create_tween()
	for i in 4:   # tremură stânga-dreapta
		var shake_x := 0.25
		if i % 2 == 1:
			shake_x = -0.25
		tween.tween_property(body, "position", origin + Vector3(shake_x, 0, 0), 0.06)
	tween.tween_property(body, "position", origin + Vector3(0, -45, 0), 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(3.0)
	tween.tween_callback(move_body_below.bind(body, origin))
	tween.tween_property(body, "position", origin, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(body.remove_meta.bind("collapsing"))


func move_body_below(body: Node3D, origin: Vector3) -> void:
	body.position = origin + Vector3(0, -8, 0)


# =====================================================================
#  DECOR (doar de aspect, fără coliziuni)
# =====================================================================
func build_decor() -> void:
	if theme == "valley":
		build_valley_decor()
	elif theme == "lava":
		build_lava_decor()
	else:
		build_cyber_decor()


func build_valley_decor() -> void:
	for i in 45:   # nori
		var pos := Vector3(random_side_x(25, 140), rng.randf_range(12, 60), rng.randf_range(-length - 60, 40))
		create_cloud(pos, rng.randf_range(2.0, 5.0))
	for i in 14:   # insule plutitoare în depărtare
		var pos := Vector3(random_side_x(35, 100), rng.randf_range(-2, 20), rng.randf_range(-length, 20))
		var r := rng.randf_range(4, 9)
		FX.add_mesh(self, FX.cyl_mesh(r, r, 1.5, 10), FX.mat(pal["top"]), pos)
		FX.add_mesh(self, FX.cyl_mesh(r * 0.95, 0.4, r * 1.6, 10), FX.mat(pal["side"]), pos + Vector3(0, -r * 0.85, 0))
		FX.add_mesh(self, FX.cyl_mesh(0.3, 0.4, 3.0, 6), FX.mat(BROWN), pos + Vector3(0, 2.2, 0))
		FX.add_mesh(self, FX.sphere_mesh(1.6, 8), FX.mat(Color(0.2, 0.65, 0.25)), pos + Vector3(0, 4.3, 0))
	for i in 10:   # munți
		var pos := Vector3(random_side_x(160, 260), FLOOR_Y, rng.randf_range(-length - 100, 50))
		var h := rng.randf_range(40, 90)
		FX.add_mesh(self, FX.cyl_mesh(0.0, h * 0.7, h, 8), FX.mat(Color(0.3, 0.55, 0.35)), pos + Vector3(0, h / 2.0, 0))


func build_lava_decor() -> void:
	for i in 12:   # vulcani
		var pos := Vector3(random_side_x(60, 170), FLOOR_Y, rng.randf_range(-length - 60, 40))
		var h := rng.randf_range(35, 90)
		FX.add_mesh(self, FX.cyl_mesh(h * 0.12, h * 0.75, h, 10), FX.mat(Color(0.2, 0.09, 0.06), 0.0, 0.0, 1.0), pos + Vector3(0, h / 2.0, 0))
		FX.add_mesh(self, FX.cyl_mesh(h * 0.11, h * 0.11, 1.0, 10), FX.mat(Color(1.0, 0.45, 0.05), 5.0), pos + Vector3(0, h, 0))
		if i % 3 == 0:   # fum din craterul unora
			var smoke := FX.make_emitter(Color(1.0, 0.4, 0.1), 40, 3.0, Vector3.UP, 20.0, 6.0, 12.0, Vector3(0, -3, 0), 1.6)
			smoke.position = pos + Vector3(0, h + 1.0, 0)
			add_child(smoke)
			smoke.emitting = true
	for i in 30:   # pietre în lavă
		var pos := Vector3(random_side_x(20, 90), FLOOR_Y + 0.5, rng.randf_range(-length, 30))
		FX.add_mesh(self, FX.sphere_mesh(rng.randf_range(1.5, 4.0), 6), FX.mat(Color(0.15, 0.08, 0.06), 0.0, 0.0, 1.0), pos)


func build_cyber_decor() -> void:
	for i in 55:   # zgârie-nori cu dungi de neon
		var pos := Vector3(random_side_x(28, 130), FLOOR_Y, rng.randf_range(-length - 80, 40))
		var h := rng.randf_range(30, 130)
		var w := rng.randf_range(6, 16)
		var tower := FX.add_mesh(self, FX.box_mesh(Vector3(w, h, w)), FX.mat(Color(0.07, 0.07, 0.13), 0.0, 0.8, 0.35), pos + Vector3(0, h / 2.0, 0))
		var stripe: Color = pal["wall"]
		if i % 2 == 0:
			stripe = pal["accent"]
		for k in int(h / 12.0):
			FX.add_mesh(tower, FX.box_mesh(Vector3(w + 0.1, 0.3, w + 0.1)), FX.mat(stripe, 4.0), Vector3(0, -h / 2.0 + 6.0 + k * 12.0, 0))
	for i in int(length / 60.0):   # inele mari deasupra traseului
		FX.add_mesh(self, FX.torus_mesh(14.0, 14.4, 48), FX.mat(pal["wall"], 3.0, 0.0, 0.5, 0.5), Vector3(0, 8, -i * 60.0 - 30.0), Vector3(PI / 2, 0, 0))
	for i in 9:   # grila de pe podea: linii pe lungime
		FX.add_mesh(self, FX.box_mesh(Vector3(0.25, 0.1, length + 300)), FX.mat(pal["accent"], 3.0), Vector3(-40.0 + i * 10.0, FLOOR_Y + 0.05, -length / 2.0))
	for i in int((length + 200) / 20.0):   # ... și pe lățime
		FX.add_mesh(self, FX.box_mesh(Vector3(90, 0.1, 0.25)), FX.mat(pal["accent"], 2.0), Vector3(0, FLOOR_Y + 0.05, 60.0 - i * 20.0))


func create_cloud(pos: Vector3, size: float) -> void:
	var white := FX.mat(Color(1, 1, 1), 0.2, 0.0, 1.0)
	for i in rng.randi_range(3, 5):
		var radius := size * rng.randf_range(0.7, 1.2)
		var offset := Vector3(i * size * 0.9 - size * 1.5, rng.randf_range(-0.4, 0.6) * size, rng.randf_range(-0.5, 0.5) * size)
		FX.add_mesh(self, FX.sphere_mesh(radius, 8), white, pos + offset)
