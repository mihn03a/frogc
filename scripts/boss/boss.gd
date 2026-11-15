extends AnimatableBody3D
## =====================================================================
##  BOSS.GD - boss-ul final "THE BIG NIC"
## =====================================================================
##  Trei faze, în funcție de viața rămasă:
##   Faza 1 (100-66%): cercuri de mingi + focuri țintite
##   Faza 2 (66-33%):  + SLAM (lovește podeaua, unda de șoc te rănește,
##                       apoi e amețit -> sari pe el!)
##   Faza 3 (33-0%):   + ploaie de blocuri, atacuri mai dese
##
##  Cum îl rănești: aterizezi pe capul lui (folosește trambulinele)
##  sau îi trimiți mingile înapoi cu un Perfect Bounce.
##
##  Boss-ul e un "automat cu stări" (state machine): variabila `state`
##  spune ce face acum, iar fiecare stare are funcția ei.
##   idle -> fight -> slam_prep -> slam -> dizzy -> rise -> fight ... -> dead
## =====================================================================

signal defeated

const BossModel = preload("res://scripts/boss/boss_model.gd")
const MAX_HP := 100.0
const HOVER_HEIGHT := 7.5               # cât de sus plutește
const ATTACK_DELAYS := [3.0, 2.5, 1.9]  # secunde între atacuri, pe faze

var hp := MAX_HP
var player: Node3D
var pool
var center := Vector3.ZERO   # centrul arenei
var state := "idle"
var model

var clock := 0.0
var state_time := 0.0        # de cât timp e în starea curentă
var attack_timer := 2.5
var attack_count := 0
var hit_cooldown := 0.0      # ca să nu fie lovit de 2 ori în aceeași clipă
var orbit_angle := PI / 2    # unde se află pe cercul din jurul arenei
var slam_target := Vector3.ZERO
var shockwave_radius := -1.0 # -1 = nu există undă de șoc
var shockwave_center := Vector3.ZERO
var shockwave_mesh: MeshInstance3D
var warning_mesh: MeshInstance3D   # cercul roșu unde va lovi


func setup(target: Node3D, projectile_pool, arena_center: Vector3) -> void:
	player = target
	pool = projectile_pool
	center = arena_center


# =====================================================================
#  PORNIRE
# =====================================================================
func _ready() -> void:
	add_to_group("boss")
	sync_to_physics = false
	collision_layer = 4
	collision_mask = 0
	var shape := SphereShape3D.new()
	shape.radius = 2.6
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	model = BossModel.new()
	add_child(model)
	position = center + Vector3(0, HOVER_HEIGHT, -9)
	create_slam_visuals()


func create_slam_visuals() -> void:
	shockwave_mesh = FX.add_mesh(self, FX.torus_mesh(0.92, 1.0, 48), FX.mat(Color(1.0, 0.3, 0.8), 4.0))
	shockwave_mesh.top_level = true    # nu se mișcă odată cu boss-ul
	shockwave_mesh.visible = false
	warning_mesh = FX.add_mesh(self, FX.cyl_mesh(3.0, 3.0, 0.08, 24), FX.mat(Color(1, 0.1, 0.1), 2.0, 0, 0.5, 0.5))
	warning_mesh.top_level = true
	warning_mesh.visible = false


func start_fight() -> void:
	state = "fight"
	attack_timer = 2.0
	AudioManager.play("boss_roar")
	AudioManager.play_music("boss")
	GameState.boss_health_changed.emit(hp, MAX_HP)
	model.set_mood("angry")


func phase() -> int:
	if hp > 66.0:
		return 1
	if hp > 33.0:
		return 2
	return 3


func change_state(new_state: String) -> void:
	state = new_state
	state_time = 0.0


# =====================================================================
#  ÎN FIECARE CADRU
# =====================================================================
func _physics_process(delta: float) -> void:
	clock += delta
	update_shockwave(delta)
	if state == "idle" or state == "dead":
		return
	hit_cooldown -= delta
	state_time += delta
	turn_toward_player(delta)
	if state == "fight":
		do_fight(delta)
	elif state == "slam_prep":
		do_slam_prep(delta)
	elif state == "slam":
		do_slam(delta)
	elif state == "dizzy":
		do_dizzy()
	elif state == "rise":
		do_rise(delta)


func do_fight(delta: float) -> void:
	# Zboară în cerc în jurul arenei și atacă din când în când.
	orbit_angle += delta * (0.3 + phase() * 0.12)
	var target := center + Vector3(cos(orbit_angle) * 9.0, HOVER_HEIGHT + sin(clock * 2.0) * 0.8, sin(orbit_angle) * 9.0)
	position = position.lerp(target, 1.0 - exp(-delta * 2.0))
	attack_timer -= delta
	if attack_timer <= 0.0:
		choose_attack()


func do_slam_prep(delta: float) -> void:
	# Se ridică deasupra țintei; cercul roșu arată unde va lovi.
	var above := Vector3(slam_target.x, center.y + HOVER_HEIGHT + 3.0, slam_target.z)
	position = position.lerp(above, 1.0 - exp(-delta * 4.0))
	warning_mesh.global_position = Vector3(slam_target.x, center.y + 0.1, slam_target.z)
	warning_mesh.scale = Vector3.ONE * (1.0 + sin(clock * 20.0) * 0.1)
	if state_time > 1.0:
		change_state("slam")


func do_slam(delta: float) -> void:
	# Cade foarte repede spre podea.
	position.y = move_toward(position.y, center.y + 2.7, 40.0 * delta)
	if position.y <= center.y + 2.75:
		slam_impact()


func do_dizzy() -> void:
	# Stă pe jos amețit 2,6 secunde - momentul perfect să sari pe el.
	if state_time > 2.6:
		change_state("rise")
		model.set_mood("angry")


func do_rise(delta: float) -> void:
	position.y = move_toward(position.y, center.y + HOVER_HEIGHT, 7.0 * delta)
	if absf(position.y - (center.y + HOVER_HEIGHT)) < 0.1:
		state = "fight"
		attack_timer = 1.5


func turn_toward_player(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > 0.5:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-to_player.x, -to_player.z), delta * 5.0)


# =====================================================================
#  ATACURI
# =====================================================================
func choose_attack() -> void:
	var p := phase()
	attack_count += 1
	attack_timer = ATTACK_DELAYS[p - 1]
	if p >= 2 and attack_count % 3 == 0:
		start_slam()
	elif p >= 3 and attack_count % 3 == 1:
		block_rain()
	elif attack_count % 2 == 0:
		aimed_shots()
	else:
		ring_of_orbs()


func ring_of_orbs() -> void:
	# Un cerc de mingi în toate direcțiile.
	var count := 10 + phase() * 2
	var start_angle := randf() * TAU
	for i in count:
		var angle := start_angle + i * TAU / count
		var direction := Vector3(cos(angle), -0.22, sin(angle)).normalized()
		pool.fire(global_position + direction * 3.0, direction * (10.0 + phase()), Color(1.0, 0.85, 0.2), 0.6, 12.0, self)
	model.attack_pose()
	AudioManager.play("boss_shoot")


func aimed_shots() -> void:
	# 3 sau 5 mingi țintite puțin în fața jucătorului.
	if player == null:
		return
	var player_velocity: Vector3 = player.get("velocity")
	var aim := player.global_position + player_velocity * 0.3
	var direction := (aim - global_position).normalized()
	var count := 5
	if phase() == 1:
		count = 3
	for i in count:
		var shot_dir := direction.rotated(Vector3.UP, (i - (count - 1) / 2.0) * 0.16)
		pool.fire(global_position + shot_dir * 3.0, shot_dir * 16.0, Color(1.0, 0.3, 0.6), 0.55, 12.0, self)
	model.attack_pose()
	AudioManager.play("boss_shoot", 0.8)


func start_slam() -> void:
	change_state("slam_prep")
	var target := center
	if player:
		target = player.global_position
	# ținta rămâne în interiorul arenei (max 15 unități de centru)
	var flat := Vector3(target.x - center.x, 0, target.z - center.z)
	if flat.length() > 15.0:
		flat = flat.normalized() * 15.0
	slam_target = center + flat
	warning_mesh.visible = true
	AudioManager.play("boss_roar", 1.3)
	GameState.show_message.emit("SLAM INCOMING - GET AIRBORNE!", Color(1.0, 0.4, 0.3))


func slam_impact() -> void:
	change_state("dizzy")
	warning_mesh.visible = false
	shockwave_radius = 2.5
	shockwave_center = Vector3(position.x, center.y + 0.3, position.z)
	shockwave_mesh.visible = true
	FX.shake(0.8)
	FX.burst(shockwave_center, Color(1.0, 0.4, 0.9), 32, 14.0, 0.5)
	AudioManager.play("slam")
	model.set_mood("dizzy")
	GameState.show_message.emit("HE'S DIZZY - STOMP HIM!", Color(1.0, 1.0, 0.4))


func update_shockwave(delta: float) -> void:
	# Inelul se mărește; dacă jucătorul e pe jos când trece inelul -> damage.
	if shockwave_radius < 0.0:
		return
	shockwave_radius += 15.0 * delta
	shockwave_mesh.global_position = shockwave_center
	shockwave_mesh.scale = Vector3(shockwave_radius, 1.5, shockwave_radius)
	if player and is_instance_valid(player):
		check_shockwave_hit()
	if shockwave_radius > 27.0:
		shockwave_radius = -1.0
		shockwave_mesh.visible = false


func check_shockwave_hit() -> void:
	var offset := player.global_position - shockwave_center
	var height := offset.y
	offset.y = 0.0
	var on_the_ring := absf(offset.length() - shockwave_radius) < 1.3
	var on_the_ground := height < 1.8
	if on_the_ring and on_the_ground:
		player.call("take_damage", 15.0, (offset.normalized() + Vector3.UP).normalized())


func block_rain() -> void:
	# Marchează 6 locuri lângă jucător, apoi după 0,7 s cad blocuri acolo.
	if player == null:
		return
	AudioManager.play("boss_roar", 1.6)
	var targets: Array[Vector3] = []
	for i in 6:
		var offset := Vector3(randf_range(-7, 7), 0, randf_range(-7, 7))
		if i == 0:
			offset = Vector3.ZERO   # primul cade exact pe jucător
		var spot := player.global_position + offset
		spot.y = center.y
		targets.append(spot)
		FX.burst(spot + Vector3.UP * 0.3, Color(1, 0.2, 0.2), 16, 3.0, 0.4, 0.0)
	await get_tree().create_timer(0.7).timeout
	if state == "dead":
		return
	for spot in targets:
		pool.fire(spot + Vector3.UP * 26.0, Vector3.DOWN * 20.0, Color(0.7, 0.2, 1.0), 1.2, 15.0, null)


# =====================================================================
#  DAMAGE ȘI MOARTE
# =====================================================================
func take_hit(damage: float, pos: Vector3) -> void:
	if state == "dead" or state == "idle" or hit_cooldown > 0.0:
		return
	hit_cooldown = 0.6
	hp = maxf(hp - damage, 0.0)
	GameState.boss_health_changed.emit(hp, MAX_HP)
	GameState.add_score(500)
	model.hit_flash()
	AudioManager.play("boss_hit")
	FX.burst(pos, Color(1.0, 1.0, 0.3), 30, 10.0, 0.4)
	FX.shake(0.4)
	FX.popup(global_position + Vector3.UP * 4.0, "-%d" % int(damage), Color(1.0, 0.4, 0.3), 96)
	if hp <= 0.0:
		die()
		return
	if state != "dizzy":
		show_hurt_face()


func show_hurt_face() -> void:
	model.set_mood("hurt")
	await get_tree().create_timer(0.5).timeout
	if state != "dead" and state != "dizzy":
		model.set_mood("angry")


func die() -> void:
	state = "dead"
	collision_layer = 0
	warning_mesh.visible = false
	pool.clear_all()
	GameState.on_boss_defeated()
	AudioManager.stop_music()
	AudioManager.play("boss_roar", 0.7)
	GameState.show_message.emit("THE BIG NIC DEFEATED!", Color(1.0, 0.9, 0.3))
	model.set_mood("cry")
	FX.flash(Color(1, 1, 1), 0.6)
	# cade pe podea, sărind ca o minge
	var tween := create_tween()
	tween.tween_property(self, "position:y", center.y + 3.0, 1.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	for i in 6:   # explozii
		var offset := Vector3(randf_range(-3, 3), randf_range(0, 4), randf_range(-3, 3))
		FX.burst(global_position + offset, Color(1.0, randf(), 0.3), 32, 12.0, 0.5)
		await get_tree().create_timer(0.3).timeout
	defeated.emit()
