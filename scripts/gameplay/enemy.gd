extends AnimatableBody3D
## =====================================================================
##  ENEMY.GD - inamicii din niveluri
## =====================================================================
##  Tipuri:
##   "fly"    (vale)    plutește și se plimbă stânga-dreapta
##   "hornet" (vale 2)  se plimbă, apoi se năpustește spre jucător
##   "bat"    (lavă)    se plimbă și trage cu mingi de foc
##   "drone"  (cyber)   se rotește și trage câte 3 lasere odată
##
##  Cum îi învingi: sari pe ei de sus, lovește-i cu SPACE apăsat (Perfect)
##  sau cu power-up-ul Super Bounce.
## =====================================================================

var type := "fly"
var contact_damage := 12.0     # cât te rănește dacă îl atingi (citit de player.gd)
var player: Node3D
var pool                       # proiectilele refolosibile

var start_pos := Vector3.ZERO  # de aici pornește mișcarea
var clock := 0.0
var phase := 0.0               # decalaj aleator, ca să nu se miște toți la fel
var shoot_timer := 2.0
var dashing := false           # doar pentru "hornet"
var dash_dir := Vector3.ZERO
var dash_time := 0.0
var dead := false
var body_color := Color.WHITE
var wings: Array[Node3D] = []
var visual: Node3D             # tot ce se vede (îl strivim când moare)


func setup(enemy_type: String, target: Node3D, projectile_pool) -> void:
	type = enemy_type
	player = target
	pool = projectile_pool


# =====================================================================
#  PORNIRE
# =====================================================================
func _ready() -> void:
	add_to_group("enemy")
	sync_to_physics = false
	collision_layer = 4     # stratul 3 = inamici
	collision_mask = 0
	start_pos = position
	phase = randf() * TAU
	shoot_timer = randf_range(1.0, 2.5)
	var shape := SphereShape3D.new()
	shape.radius = 1.1
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	visual = Node3D.new()
	add_child(visual)
	build_look()


func build_look() -> void:
	var eye_material := FX.mat(Color(1.0, 0.15, 0.1), 2.5)
	var wing_material := FX.mat(Color(0.9, 0.95, 1.0), 0.3, 0.0, 0.2, 0.55)
	if type == "fly":
		build_fly()
	elif type == "hornet":
		build_hornet()
	elif type == "bat":
		build_bat()
		wing_material = FX.mat(Color(0.25, 0.05, 0.05))
		eye_material = FX.mat(Color(1.0, 0.85, 0.1), 3.0)
	elif type == "drone":
		build_drone()
		eye_material = FX.mat(Color(1.0, 0.1, 0.4), 4.0)
	add_eyes(eye_material)
	if type != "drone":
		add_wings(wing_material)


func build_fly() -> void:
	body_color = Color(0.25, 0.3, 0.45)
	contact_damage = 10.0
	FX.add_mesh(visual, FX.sphere_mesh(0.8, 12), FX.mat(body_color, 0.0, 0.3, 0.4), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.9, 1.2))


func build_hornet() -> void:
	body_color = Color(1.0, 0.8, 0.1)
	contact_damage = 14.0
	FX.add_mesh(visual, FX.sphere_mesh(0.8, 12), FX.mat(body_color), Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 0.9, 1.4))
	for i in 2:   # dungi negre
		FX.add_mesh(visual, FX.torus_mesh(0.62, 0.85, 16), FX.mat(Color(0.08, 0.08, 0.08)), Vector3(0, 0, 0.1 + i * 0.4), Vector3(PI / 2, 0, 0))
	# acul
	FX.add_mesh(visual, FX.cyl_mesh(0.0, 0.2, 0.7, 8), FX.mat(Color(0.1, 0.1, 0.1)), Vector3(0, 0, 1.3), Vector3(PI / 2, 0, 0))


func build_bat() -> void:
	body_color = Color(0.55, 0.1, 0.08)
	contact_damage = 15.0
	FX.add_mesh(visual, FX.sphere_mesh(0.8, 10), FX.mat(body_color, 0.4), Vector3.ZERO)
	for side in [-1.0, 1.0]:   # urechi
		FX.add_mesh(visual, FX.cyl_mesh(0.0, 0.18, 0.5, 6), FX.mat(body_color), Vector3(side * 0.4, 0.8, 0))


func build_drone() -> void:
	body_color = Color(0.2, 0.9, 1.0)
	contact_damage = 16.0
	FX.add_mesh(visual, FX.box_mesh(Vector3(1.4, 0.7, 1.4)), FX.mat(Color(0.15, 0.17, 0.22), 0.0, 0.9, 0.3))
	FX.add_mesh(visual, FX.torus_mesh(1.2, 1.35, 24), FX.mat(body_color, 3.0), Vector3(0, 0.2, 0))


func add_eyes(material: Material) -> void:
	# Ochii privesc spre +Z, pentru că jucătorul vine din acea parte.
	for side in [-1.0, 1.0]:
		FX.add_mesh(visual, FX.sphere_mesh(0.25, 8), material, Vector3(side * 0.33, 0.25, 0.7))


func add_wings(material: Material) -> void:
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.position = Vector3(side * 0.6, 0.3, 0)
		visual.add_child(wing)
		FX.add_mesh(wing, FX.box_mesh(Vector3(1.4, 0.05, 0.7)), material, Vector3(side * 0.7, 0, 0))
		wings.append(wing)


# =====================================================================
#  ÎN FIECARE CADRU
# =====================================================================
func _physics_process(delta: float) -> void:
	if dead or player == null or not is_instance_valid(player):
		return
	# distance > 0 înseamnă că jucătorul se apropie
	var distance := player.global_position.z - global_position.z
	if absf(distance) > 110.0:
		return   # prea departe: nu facem nimic (economisim performanță)
	clock += delta
	flap_wings()
	if type == "fly":
		position = start_pos + Vector3(sin(clock * 1.5 + phase) * 4.0, sin(clock * 3.0 + phase) * 0.8, 0)
	elif type == "hornet":
		move_hornet(delta, distance)
	elif type == "bat":
		position = start_pos + Vector3(sin(clock * 1.2 + phase) * 5.0, sin(clock * 2.4) * 1.2, 0)
		try_shoot(delta, distance, 2.2, 1)
	elif type == "drone":
		visual.rotate_y(delta * 2.0)
		position = start_pos + Vector3(cos(clock * 1.4 + phase) * 3.5, sin(clock * 2.0) * 1.0, sin(clock * 1.4 + phase) * 2.0)
		try_shoot(delta, distance, 2.6, 3)


func flap_wings() -> void:
	for wing in wings:
		wing.rotation.z = sin(clock * 32.0) * 0.6 * signf(wing.position.x)


func move_hornet(delta: float, distance: float) -> void:
	if dashing:
		dash_time += delta
		position += dash_dir * 24.0 * delta
		if dash_time > 2.5:   # după 2,5 s se întoarce la locul lui
			dashing = false
			position = start_pos
		return
	position = start_pos + Vector3(sin(clock * 2.0 + phase) * 3.0, sin(clock * 4.0) * 0.5, 0)
	if distance > 8.0 and distance < 30.0:
		start_dash()


func start_dash() -> void:
	dashing = true
	dash_time = 0.0
	dash_dir = (player.global_position - global_position).normalized()
	AudioManager.play("enemy_shoot", 0.6)


func try_shoot(delta: float, distance: float, interval: float, count: int) -> void:
	if distance < 10.0 or distance > 50.0 or pool == null:
		return
	shoot_timer -= delta
	if shoot_timer > 0.0:
		return
	shoot_timer = interval
	# Țintește puțin în fața jucătorului (unde VA fi, nu unde e acum).
	var player_velocity: Vector3 = player.get("velocity")
	var aim := player.global_position + player_velocity * 0.45
	var direction := (aim - global_position).normalized()
	var color := Color(0.3, 1.0, 1.0)
	if type == "bat":
		color = Color(1.0, 0.5, 0.1)
	for i in count:
		# împrăștiem proiectilele ca un evantai
		var spread := (i - (count - 1) / 2.0) * 0.18
		var shot_dir := direction.rotated(Vector3.UP, spread)
		pool.fire(global_position + shot_dir * 1.6, shot_dir * 17.0, color, 0.45, 12.0, self)
	AudioManager.play("enemy_shoot")


# =====================================================================
#  MOARTEA
# =====================================================================
func defeat() -> void:
	if dead:
		return
	dead = true
	remove_from_group("enemy")
	collision_layer = 0
	GameState.on_enemy_defeated()
	var points := GameState.add_score(200)
	GameState.add_evo(5)
	FX.popup(global_position + Vector3.UP * 1.5, "SPLAT! +%d" % points, Color(1.0, 0.65, 0.2), 60)
	FX.burst(global_position, body_color, 30, 9.0, 0.35)
	AudioManager.play("enemy_die")
	# animație: se turtește, apoi dispare
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3(1.7, 0.15, 1.7), 0.12)
	tween.tween_property(visual, "scale", Vector3.ZERO, 0.12)
	tween.tween_callback(queue_free)
