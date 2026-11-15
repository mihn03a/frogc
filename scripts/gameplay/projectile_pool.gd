extends Node3D
## =====================================================================
##  PROJECTILE_POOL.GD - toate proiectilele din joc
## =====================================================================
##  (gloanțele inamicilor, mingile boss-ului, blocurile care cad)
##
##  "Object pooling": creăm 64 de proiectile O SINGURĂ DATĂ la început și
##  le refolosim. E mult mai rapid decât să creăm și să ștergem obiecte
##  în timpul jocului.
##
##  Un Perfect Bounce (player.try_reflect) trimite proiectilul ÎNAPOI
##  spre cel care l-a tras - de aici numele temei: BOUNCE BACK!
## =====================================================================

const POOL_SIZE := 64
const PARKING_SPOT := Vector3(0, -500, 0)   # aici "ascundem" proiectilele nefolosite

# Fiecare proiectil e un dicționar:
#  area     - zona care detectează lovitura
#  mesh     - bila care se vede
#  velocity - viteza
#  life     - secunde rămase până dispare
#  friendly - true dacă a fost trimis înapoi de jucător
#  active   - true dacă e în zbor
#  damage   - cât rănește
#  shooter  - cine l-a tras (ținta când e trimis înapoi)
var shots: Array[Dictionary] = []
var next_index := 0


func _ready() -> void:
	for i in POOL_SIZE:
		shots.append(create_shot(i))


func create_shot(index: int) -> Dictionary:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1 | 2 | 4   # lume, jucător, inamici
	area.monitorable = false
	area.monitoring = true            # mereu pornit; cele nefolosite stau departe
	area.visible = false
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.mesh = FX.sphere_mesh(0.5, 10)
	area.add_child(mesh)
	add_child(area)
	area.position = PARKING_SPOT
	area.body_entered.connect(on_shot_hit.bind(index))
	return {"area": area, "mesh": mesh, "velocity": Vector3.ZERO, "life": 0.0,
		"friendly": false, "active": false, "damage": 12.0, "shooter": null}


# =====================================================================
#  TRAGEREA
# =====================================================================
func find_free_shot() -> int:
	# Căutăm un proiectil care nu e în zbor (întoarce -1 dacă toate sunt ocupate).
	for k in POOL_SIZE:
		var index := (next_index + k) % POOL_SIZE
		if not shots[index]["active"]:
			return index
	return -1


func fire(pos: Vector3, velocity: Vector3, color: Color, size: float = 0.5, damage: float = 12.0, shooter: Node3D = null) -> void:
	var index := find_free_shot()
	if index == -1:
		return
	next_index = (index + 1) % POOL_SIZE
	var shot := shots[index]
	var area: Area3D = shot["area"]
	area.global_position = pos
	area.scale = Vector3.ONE * (size / 0.5)
	area.visible = true
	set_shot_color(shot, color, 3.0)
	shot["velocity"] = velocity
	shot["life"] = 6.0
	shot["friendly"] = false
	shot["active"] = true
	shot["damage"] = damage
	shot["shooter"] = shooter


func set_shot_color(shot: Dictionary, color: Color, glow: float) -> void:
	var mesh: MeshInstance3D = shot["mesh"]
	mesh.material_override = FX.mat(color, glow)


func clear_all() -> void:
	for i in POOL_SIZE:
		if shots[i]["active"]:
			put_away(i)


func put_away(index: int) -> void:
	var shot := shots[index]
	shot["active"] = false
	var area: Area3D = shot["area"]
	area.visible = false
	# set_deferred: nu mutăm corpuri fizice chiar în timpul unei coliziuni
	area.set_deferred("position", PARKING_SPOT)


# =====================================================================
#  ÎN FIECARE CADRU: mișcăm proiectilele active
# =====================================================================
func _physics_process(delta: float) -> void:
	for i in POOL_SIZE:
		var shot := shots[i]
		if not shot["active"]:
			continue
		if shot["friendly"]:
			steer_toward_shooter(shot, delta)
		var area: Area3D = shot["area"]
		var velocity: Vector3 = shot["velocity"]
		area.global_position += velocity * delta
		shot["life"] = float(shot["life"]) - delta
		if shot["life"] <= 0.0:
			put_away(i)


func steer_toward_shooter(shot: Dictionary, delta: float) -> void:
	# Proiectilul trimis înapoi "urmărește" pe cel care l-a tras.
	var target = shot["shooter"]
	if target == null or not is_instance_valid(target):
		return
	var area: Area3D = shot["area"]
	var velocity: Vector3 = shot["velocity"]
	var wanted: Vector3 = (target.global_position - area.global_position).normalized() * velocity.length()
	shot["velocity"] = velocity.lerp(wanted, minf(delta * 4.0, 1.0))


# =====================================================================
#  CÂND UN PROIECTIL LOVEȘTE CEVA
# =====================================================================
func on_shot_hit(body, index: int) -> void:
	var shot := shots[index]
	if not shot["active"]:
		return
	if body.is_in_group("player"):
		hit_player(body, shot, index)
	elif body.is_in_group("boss"):
		if shot["friendly"]:
			var area: Area3D = shot["area"]
			body.take_hit(7.0, area.global_position)
			put_away(index)
	elif body.is_in_group("enemy"):
		if shot["friendly"]:
			body.defeat()
			put_away(index)
	else:
		# a lovit un perete / o platformă
		var area: Area3D = shot["area"]
		FX.burst(area.global_position, Color(1.0, 0.8, 0.5), 8, 4.0, 0.2)
		put_away(index)


func hit_player(player, shot: Dictionary, index: int) -> void:
	if shot["friendly"]:
		return   # propriul proiectil trimis înapoi nu-l rănește
	if player.try_reflect():
		send_back(shot)
		return
	var area: Area3D = shot["area"]
	var direction: Vector3 = (player.global_position - area.global_position).normalized()
	player.take_damage(float(shot["damage"]), direction)
	FX.burst(area.global_position, Color(1.0, 0.5, 0.2), 12, 6.0, 0.25)
	put_away(index)


func send_back(shot: Dictionary) -> void:
	# BOUNCE BACK: proiectilul se întoarce mai repede și devine verde.
	shot["friendly"] = true
	var velocity: Vector3 = shot["velocity"]
	shot["velocity"] = -velocity * 1.4
	shot["life"] = 4.0
	set_shot_color(shot, Color(0.4, 1.0, 0.4), 4.0)
