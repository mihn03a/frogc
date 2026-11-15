extends Node3D
## =====================================================================
##  PLAYER_MODEL.GD - cum arată broasca-avion
## =====================================================================
##  Broasca e construită din forme simple și are 5 evoluții vizibile:
##   1: aripi mici, elice de lemn
##   2: aripi mai mari cu vârfuri galbene
##   3: armură metalică, elice dublă aurie
##   4: motoare cu reacție pe aripi
##   5: crom, dungi de neon, inel în jurul corpului
##  Privește spre -Z. Se apelează build(evoluție).
##
##  Fața: în loc de ochi și gură, broasca poartă fața unui prieten
##  (assets/textures/friend_face.png), pusă pe o mască ușor curbată.
##  Dacă poza lipsește, broasca primește înapoi ochii și gura obișnuite.
##
##  Animațiile sunt făcute din cod (fără schelet importat):
##   poze (pose):      "fly", "idle", "showcase", "victory", "sad"
##   expresii:         "happy", "serious", "sad", "hurt"
## =====================================================================

const FROG_GREEN := Color(0.36, 0.8, 0.26)
const BELLY := Color(0.88, 0.96, 0.62)
const WING_COLORS := [Color(0.92, 0.26, 0.2), Color(1.0, 0.6, 0.12), Color(0.62, 0.66, 0.72), Color(0.16, 0.3, 0.75), Color(0.1, 0.11, 0.14)]
const WING_SPANS := [1.5, 2.4, 2.5, 2.7, 3.0]   # aripile cresc cu fiecare evoluție
const USE_FRIEND_FACE := true                    # false = ochii și gura de broască
const FACE_TEXTURE_PATH := "res://assets/textures/friend_face.png"
const FACE_SIZE := 1.4                           # lățimea măștii cu fața
const FACE_CENTER := Vector3(0, 0.62, -1.75)     # în fața capului și a elicei

# ---------------------------------------------------------------- variabile publice
var stage := 1
var pose := "fly"
var expression := "happy"
var bank := 0.0                                 # înclinarea în viraj (-1..1)
var pitch := 0.0                                # botul în sus / în jos (-1..1)
var body_color_override := Color(0, 0, 0, 0)   # dacă alpha > 0, folosim culoarea asta (Battle)
var outfit := ""                                # "" sau "suit" (easter egg-ul de la final)

# ---------------------------------------------------------------- variabile interne
var clock := 0.0
var squash_amount := 0.0      # 1 = turtit complet, revine singur la 0
var blinking := false         # clipește (după ce a fost lovit)
var hurt_time := 0.0
var size_multiplier := 1.0    # broasca e puțin mai mare la fiecare evoluție
var root: Node3D              # tot corpul
var propeller: Node3D
var left_arm: Node3D
var right_arm: Node3D
var hands: Array[Node3D] = []
var left_brow: Node3D
var right_brow: Node3D
var mouth_left: Node3D        # gura are 2 jumătăți: se pot înclina în zâmbet sau supărare
var mouth_right: Node3D
var pupils: Array[Node3D] = []
var halo: Node3D
var cuffs: Array[Node3D] = []
var chain_links: Array[Node3D] = []
var face_mask: MeshInstance3D       # masca cu fața prietenului (null dacă nu e folosită)
var face_material: StandardMaterial3D
static var face_texture: Texture2D  # poza se încarcă o singură dată, pentru toate broaștele

# materialele, alese în choose_materials()
var skin_material: StandardMaterial3D
var wing_material: StandardMaterial3D
var armor_material: StandardMaterial3D
var chrome_material: StandardMaterial3D
var neon_material: StandardMaterial3D
var body_color: Color


# =====================================================================
#  CONSTRUCȚIA BROAȘTEI
# =====================================================================
func build(new_stage: int) -> void:
	stage = clampi(new_stage, 1, 5)
	if root:
		root.queue_free()   # ștergem modelul vechi
	root = Node3D.new()
	add_child(root)
	pupils.clear()
	hands.clear()
	cuffs.clear()
	chain_links.clear()
	halo = null
	forget_face_parts()
	size_multiplier = 1.0 + (stage - 1) * 0.07
	choose_materials()
	var friend_face := get_face_texture()
	build_body(friend_face == null)
	if friend_face:
		build_friend_face(friend_face)
	else:
		for side in [-1.0, 1.0]:
			build_eye(side)
		build_mouth()
	for side in [-1.0, 1.0]:
		build_arm(side)
	for side in [-1.0, 1.0]:
		build_wing(side)
	build_tail()
	build_propeller()
	build_armor()
	if outfit == "suit":
		add_suit()
	set_expression(expression)


func choose_materials() -> void:
	var skin: Dictionary = GameState.current_skin()
	body_color = skin["color"]
	if skin["id"] == "classic" and stage >= 5:
		body_color = Color(0.22, 0.85, 0.55)
	if body_color_override.a > 0.0:
		body_color = body_color_override
		skin = {"id": "battle", "emission": 0.0, "metal": 0.0}
	var metal_amount := float(skin["metal"])
	skin_material = FX.mat(body_color, float(skin["emission"]), metal_amount, 0.55 - metal_amount * 0.3)
	var wing_metal := 0.0
	if stage >= 3:
		wing_metal = 0.5
	wing_material = FX.mat(WING_COLORS[stage - 1], 0.0, wing_metal, 0.45)
	chrome_material = FX.mat(Color(0.14, 0.16, 0.2), 0.0, 0.9, 0.25)
	neon_material = FX.mat(Color(0.2, 1.0, 1.0), 4.0)
	armor_material = FX.mat(Color(0.7, 0.72, 0.78), 0.0, 0.85, 0.3)
	if stage >= 5:
		armor_material = chrome_material


func build_body(with_cheeks: bool) -> void:
	FX.add_mesh(root, FX.sphere_mesh(1.0, 16), skin_material, Vector3.ZERO, Vector3.ZERO, Vector3(1.05, 0.85, 1.35))
	FX.add_mesh(root, FX.sphere_mesh(0.8, 14), FX.mat(BELLY, 0.0, 0.0, 0.6), Vector3(0, -0.28, -0.25), Vector3.ZERO, Vector3(0.95, 0.65, 1.15))
	if not with_cheeks:
		return
	for side in [-1.0, 1.0]:   # obrajii roz
		FX.add_mesh(root, FX.sphere_mesh(0.12, 8), FX.mat(Color(1.0, 0.5, 0.5)), Vector3(side * 0.7, 0.2, -1.05))


func build_eye(side: float) -> void:
	var white := FX.mat(Color(1, 1, 1), 0.0, 0.0, 0.3)
	var black := FX.mat(Color(0.05, 0.05, 0.06), 0.0, 0.0, 0.2)
	FX.add_mesh(root, FX.sphere_mesh(0.48, 14), skin_material, Vector3(side * 0.46, 0.66, -0.5))
	FX.add_mesh(root, FX.sphere_mesh(0.42, 14), white, Vector3(side * 0.47, 0.72, -0.62))
	var pupil := Node3D.new()
	pupil.position = Vector3(side * 0.48, 0.74, -0.98)
	root.add_child(pupil)
	FX.add_mesh(pupil, FX.sphere_mesh(0.19, 10), black)
	FX.add_mesh(pupil, FX.sphere_mesh(0.06, 6), white, Vector3(side * 0.06, 0.07, -0.13))   # sclipirea din ochi
	pupils.append(pupil)
	var brow := Node3D.new()
	brow.position = Vector3(side * 0.47, 1.14, -0.72)
	root.add_child(brow)
	FX.add_mesh(brow, FX.box_mesh(Vector3(0.5, 0.1, 0.16)), FX.mat(body_color.darkened(0.45)))
	if side < 0.0:
		left_brow = brow
	else:
		right_brow = brow


func build_mouth() -> void:
	var dark := FX.mat(Color(0.12, 0.05, 0.05))
	var mouth := Node3D.new()
	mouth.position = Vector3(0, 0.22, -1.27)
	root.add_child(mouth)
	mouth_left = Node3D.new()
	mouth_left.position = Vector3(-0.24, 0, 0)
	mouth.add_child(mouth_left)
	FX.add_mesh(mouth_left, FX.box_mesh(Vector3(0.5, 0.07, 0.1)), dark)
	mouth_right = Node3D.new()
	mouth_right.position = Vector3(0.24, 0, 0)
	mouth.add_child(mouth_right)
	FX.add_mesh(mouth_right, FX.box_mesh(Vector3(0.5, 0.07, 0.1)), dark)


# =====================================================================
#  FAȚA PRIETENULUI
# =====================================================================
func forget_face_parts() -> void:
	# Bucățile feței vechi au fost șterse odată cu modelul vechi.
	left_brow = null
	right_brow = null
	mouth_left = null
	mouth_right = null
	face_mask = null
	face_material = null


func get_face_texture() -> Texture2D:
	if not USE_FRIEND_FACE:
		return null
	if face_texture == null:
		face_texture = FX.load_texture_file(FACE_TEXTURE_PATH)
	return face_texture


func build_friend_face(texture: Texture2D) -> void:
	face_mask = FX.make_face_mask(texture, FACE_SIZE, 1.7)
	face_material = face_mask.material_override
	face_mask.position = FACE_CENTER
	root.add_child(face_mask)


func update_face_for_expression(new_expression: String) -> void:
	# Poza nu-și poate schimba expresia, așa că mișcăm masca și îi schimbăm culoarea.
	if face_mask == null:
		return
	var tilt := 0.0
	var tint := Color(1, 1, 1)
	if new_expression == "sad":
		tilt = 0.25                       # se uită în jos
		tint = Color(0.8, 0.85, 1.0)      # puțin palid
	elif new_expression == "hurt":
		tint = Color(1.0, 0.6, 0.6)       # roșu de durere
	elif new_expression == "serious":
		tilt = -0.08                      # bărbia sus
	face_mask.rotation.x = tilt
	face_material.albedo_color = tint


func build_arm(side: float) -> void:
	# Brațul se rotește în jurul umărului (shoulder).
	var shoulder := Node3D.new()
	shoulder.position = Vector3(side * 0.85, -0.12, -0.55)
	root.add_child(shoulder)
	FX.add_mesh(shoulder, FX.capsule_mesh(0.14, 0.75), skin_material, Vector3(0, -0.35, 0))
	hands.append(build_hand(shoulder))
	if stage >= 4:   # protecție pe umăr
		FX.add_mesh(shoulder, FX.sphere_mesh(0.28, 8), armor_material, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	if side < 0.0:
		left_arm = shoulder
	else:
		right_arm = shoulder


func build_hand(shoulder: Node3D) -> Node3D:
	# Palmă + 3 degete cu vârfuri rotunde (palma privește înainte, spre -Z).
	var hand := Node3D.new()
	hand.position = Vector3(0, -0.74, 0)
	shoulder.add_child(hand)
	var palm := FX.mat(body_color.lightened(0.35))
	FX.add_mesh(hand, FX.sphere_mesh(0.2, 10), palm, Vector3.ZERO, Vector3.ZERO, Vector3(1.25, 1.1, 0.6))
	for finger in 3:
		var x := (finger - 1) * 0.12
		FX.add_mesh(hand, FX.capsule_mesh(0.045, 0.24), palm, Vector3(x, -0.2, 0), Vector3(0, 0, -x * 1.5))
		FX.add_mesh(hand, FX.sphere_mesh(0.06, 6), palm, Vector3(x * 1.25, -0.32, 0))
	return hand


func build_wing(side: float) -> void:
	var span: float = WING_SPANS[stage - 1]
	var wing := Node3D.new()
	wing.position = Vector3(side * 0.85, -0.05, 0.05)
	if stage >= 5:
		wing.rotation.y = side * -0.25   # aripi în formă de săgeată
	root.add_child(wing)
	FX.add_mesh(wing, FX.box_mesh(Vector3(span, 0.13, 0.95)), wing_material, Vector3(side * span * 0.5, 0, 0))
	if stage >= 2:   # vârfuri galbene
		FX.add_mesh(wing, FX.box_mesh(Vector3(0.35, 0.15, 0.97)), FX.mat(Color(1, 0.95, 0.3)), Vector3(side * (span - 0.3), 0, 0))
	if stage >= 4:
		add_wing_engine(wing, side, span)
	if stage >= 5:
		FX.add_mesh(wing, FX.box_mesh(Vector3(span, 0.06, 0.08)), neon_material, Vector3(side * span * 0.5, 0.06, -0.5))
		var tip := span * 0.9   # al doilea motor, la vârful aripii
		FX.add_mesh(wing, FX.cyl_mesh(0.17, 0.2, 1.0, 10), chrome_material, Vector3(side * tip, -0.22, 0.15), Vector3(PI / 2, 0, 0))
		add_flame(wing, Vector3(side * tip, -0.22, 0.7), Color(1.0, 0.3, 1.0))


func add_wing_engine(wing: Node3D, side: float, span: float) -> void:
	var x := span * 0.55
	FX.add_mesh(wing, FX.cyl_mesh(0.24, 0.28, 1.3, 12), armor_material, Vector3(side * x, -0.32, 0.1), Vector3(PI / 2, 0, 0))
	FX.add_mesh(wing, FX.cyl_mesh(0.2, 0.2, 0.05, 12), FX.mat(Color(1, 0.5, 0.1), 5.0), Vector3(side * x, -0.32, 0.77), Vector3(PI / 2, 0, 0))
	var flame_color := Color(0.3, 0.9, 1.0)
	if stage == 4:
		flame_color = Color(1.0, 0.55, 0.15)
	add_flame(wing, Vector3(side * x, -0.32, 0.85), flame_color)


func add_flame(parent: Node3D, pos: Vector3, color: Color) -> void:
	var flame := FX.make_emitter(color, 24, 0.35, Vector3(0, 0, 1), 8.0, 4.0, 7.0, Vector3.ZERO, 0.28)
	flame.position = pos
	parent.add_child(flame)
	flame.emitting = true


func build_tail() -> void:
	FX.add_mesh(root, FX.box_mesh(Vector3(1.7, 0.09, 0.45)), wing_material, Vector3(0, 0.12, 1.35))
	FX.add_mesh(root, FX.box_mesh(Vector3(0.09, 0.75, 0.55)), wing_material, Vector3(0, 0.5, 1.38))


func build_propeller() -> void:
	var gold := FX.mat(Color(1.0, 0.78, 0.2), 0.0, 0.9, 0.3)
	var hub_material := FX.mat(Color(0.9, 0.9, 0.9), 0.0, 0.4, 0.4)
	var blade_material := FX.mat(Color(0.35, 0.22, 0.12))   # lemn
	var blade_length := 1.6
	if stage >= 3:
		hub_material = gold
		blade_material = gold
		blade_length = 2.0
	FX.add_mesh(root, FX.cyl_mesh(0.0, 0.24, 0.4, 12), hub_material, Vector3(0, -0.32, -1.45), Vector3(-PI / 2, 0, 0))
	propeller = Node3D.new()
	propeller.position = Vector3(0, -0.32, -1.62)
	root.add_child(propeller)
	FX.add_mesh(propeller, FX.box_mesh(Vector3(0.2, blade_length, 0.05)), blade_material)
	if stage >= 3:   # elice dublă (în cruce)
		FX.add_mesh(propeller, FX.box_mesh(Vector3(blade_length, 0.2, 0.05)), blade_material)


func build_armor() -> void:
	if stage >= 3:
		FX.add_mesh(root, FX.box_mesh(Vector3(1.3, 0.25, 1.4)), armor_material, Vector3(0, 0.72, 0.42), Vector3(-0.18, 0, 0))
		FX.add_mesh(root, FX.box_mesh(Vector3(1.25, 0.45, 0.14)), armor_material, Vector3(0, -0.62, -1.08), Vector3(0.35, 0, 0))
		FX.add_mesh(root, FX.cyl_mesh(0.42, 0.48, 0.16, 12), armor_material, Vector3(0, 0.96, -0.2))
	if stage >= 4:
		FX.add_mesh(root, FX.box_mesh(Vector3(0.2, 0.5, 0.9)), armor_material, Vector3(0, 1.0, 0.5))
	if stage >= 5:
		FX.add_mesh(root, FX.box_mesh(Vector3(1.32, 0.04, 0.08)), neon_material, Vector3(0, 0.86, 0.0))
		FX.add_mesh(root, FX.cyl_mesh(0.05, 0.05, 0.6, 6), neon_material, Vector3(0.25, 1.25, 0.2), Vector3(0.4, 0, 0))
		FX.add_mesh(root, FX.cyl_mesh(0.05, 0.05, 0.6, 6), neon_material, Vector3(-0.25, 1.25, 0.2), Vector3(0.4, 0, 0))
		halo = Node3D.new()
		root.add_child(halo)
		FX.add_mesh(halo, FX.torus_mesh(2.1, 2.22, 32), FX.mat(Color(0.3, 1.0, 1.0), 3.0, 0, 0.5, 0.7))


# =====================================================================
#  COSTUMUL (easter egg-ul de la victorie)
# =====================================================================
func add_suit() -> void:
	# Sacou bej + manșete de cămașă albastră + cravată + cătușe.
	var jacket := FX.mat(Color(0.86, 0.82, 0.72), 0.0, 0.0, 0.85)
	var shirt := FX.mat(Color(0.68, 0.8, 0.96), 0.0, 0.0, 0.6)
	FX.add_mesh(root, FX.sphere_mesh(1.0, 16), jacket, Vector3(0, -0.12, 0.05), Vector3.ZERO, Vector3(1.12, 0.82, 1.4))
	FX.add_mesh(root, FX.box_mesh(Vector3(0.42, 0.55, 0.1)), shirt, Vector3(0, -0.15, -1.33), Vector3(0.2, 0, 0))
	FX.add_mesh(root, FX.box_mesh(Vector3(0.12, 0.45, 0.08)), FX.mat(Color(0.25, 0.3, 0.45)), Vector3(0, -0.18, -1.39), Vector3(0.2, 0, 0))
	for side in [-1.0, 1.0]:   # reverele sacoului
		FX.add_mesh(root, FX.box_mesh(Vector3(0.28, 0.6, 0.08)), jacket, Vector3(side * 0.28, -0.12, -1.36), Vector3(0.2, 0, side * 0.35))
	for arm in [left_arm, right_arm]:   # mânecile
		FX.add_mesh(arm, FX.capsule_mesh(0.18, 0.62), jacket, Vector3(0, -0.3, 0))
		FX.add_mesh(arm, FX.cyl_mesh(0.17, 0.17, 0.12, 12), shirt, Vector3(0, -0.6, 0))
	add_handcuffs()


func add_handcuffs() -> void:
	# Un inel de oțel pe fiecare încheietură + un lanț între ele.
	var steel := FX.mat(Color(0.82, 0.84, 0.88), 0.0, 1.0, 0.18)
	for hand in hands:
		var cuff := Node3D.new()
		cuff.position = Vector3(0, 0.14, 0)
		hand.add_child(cuff)
		FX.add_mesh(cuff, FX.torus_mesh(0.12, 0.16, 20), steel)
		FX.add_mesh(cuff, FX.box_mesh(Vector3(0.06, 0.06, 0.06)), steel, Vector3(0.15, 0, 0))
		cuffs.append(cuff)
	for i in 3:
		var link := FX.add_mesh(root, FX.torus_mesh(0.035, 0.06, 10), steel)
		link.top_level = true   # îl poziționăm manual între cele 2 cătușe
		chain_links.append(link)


func update_chain() -> void:
	# Zalele lanțului stau mereu pe linia dintre cele 2 cătușe.
	if cuffs.size() < 2 or chain_links.is_empty():
		return
	var start := cuffs[0].global_position
	var end := cuffs[1].global_position
	var direction := end - start
	var count := chain_links.size()
	for i in count:
		var link := chain_links[i]
		link.global_position = start.lerp(end, (i + 1.0) / (count + 1.0))
		if direction.length() <= 0.01:
			continue
		var up := Vector3.UP
		if absf(direction.normalized().y) >= 0.95:
			up = Vector3.FORWARD
		link.look_at(link.global_position + direction, up)
		if i % 2 == 0:   # zalele alternează: una culcată, una în picioare
			link.rotate_object_local(Vector3.RIGHT, PI / 2)


# =====================================================================
#  EXPRESII
# =====================================================================
func set_expression(new_expression: String) -> void:
	expression = new_expression
	update_face_for_expression(new_expression)
	if left_brow == null:
		return
	var brow_angle := 0.0
	var brow_height := 1.14
	var smile := 0.3          # pozitiv = zâmbet, negativ = supărare
	var pupil_height := 0.74
	if new_expression == "happy":
		brow_height = 1.2
		smile = 0.32
	elif new_expression == "serious":
		brow_angle = -0.38
		smile = 0.0
	elif new_expression == "sad":
		brow_angle = 0.42
		smile = -0.35
		pupil_height = 0.66   # se uită în jos
	elif new_expression == "hurt":
		brow_angle = 0.3
		smile = -0.2
	left_brow.rotation.z = brow_angle
	right_brow.rotation.z = -brow_angle
	left_brow.position.y = brow_height
	right_brow.position.y = brow_height
	mouth_left.rotation.z = -smile
	mouth_right.rotation.z = smile
	for pupil in pupils:
		pupil.position.y = pupil_height


func squash() -> void:
	squash_amount = 1.0


func hurt(duration: float) -> void:
	hurt_time = duration
	set_expression("hurt")


func set_blink(on: bool) -> void:
	blinking = on


# =====================================================================
#  ANIMAȚIE ÎN FIECARE CADRU
# =====================================================================
func _process(delta: float) -> void:
	if root == null:
		return
	clock += delta
	update_hurt_timer(delta)
	update_blink()
	spin_propeller_and_halo(delta)
	update_chain()
	update_squash(delta)
	if pose == "fly":
		animate_flying(delta)
	elif pose == "idle" or pose == "showcase":
		animate_idle()
	elif pose == "victory":
		animate_victory(delta)
	elif pose == "sad":
		animate_sad(delta)


func update_hurt_timer(delta: float) -> void:
	if hurt_time <= 0.0:
		return
	hurt_time -= delta
	if hurt_time <= 0.0:
		if pose == "fly":
			set_expression("happy")
		else:
			set_expression(expression)


func update_blink() -> void:
	# Când clipește, e invizibilă jumătate din fiecare 0,14 secunde.
	var hidden := blinking and fmod(clock, 0.14) < 0.07
	root.visible = not hidden


func spin_propeller_and_halo(delta: float) -> void:
	if propeller:
		var speed := 28.0
		if pose == "sad":
			speed = 3.0   # elicea aproape oprită când e tristă
		propeller.rotate_z(delta * speed)
	if halo:
		halo.rotation.x = sin(clock * 1.3) * 0.25   # inel ca la planeta Saturn
		halo.rotate_y(delta * 2.0)


func update_squash(delta: float) -> void:
	squash_amount = move_toward(squash_amount, 0.0, delta * 5.0)
	var amount := squash_amount * 0.32
	# mai lată și mai scundă când e turtită
	root.scale = Vector3(1.0 + amount, 1.0 - amount, 1.0 + amount) * size_multiplier


func animate_flying(delta: float) -> void:
	rotation.z = lerp_angle(rotation.z, -bank * 0.6, delta * 8.0)
	rotation.x = lerpf(rotation.x, pitch * 0.4, delta * 6.0)
	root.position.y = sin(clock * 3.0) * 0.08
	left_arm.rotation = Vector3(1.3 + sin(clock * 6.0) * 0.1, 0, -0.2)
	right_arm.rotation = Vector3(1.3 + sin(clock * 6.0 + 1.0) * 0.1, 0, 0.2)


func animate_idle() -> void:
	# Se leagănă și dă din mâini (în meniu și pe ecranul de evoluție).
	rotation.z = sin(clock * 1.2) * 0.08
	rotation.x = 0.0
	root.position.y = sin(clock * 2.0) * 0.15
	left_arm.rotation = Vector3(0.4, 0, -0.5 - sin(clock * 3.0) * 0.3)
	right_arm.rotation = Vector3(0.4, 0, 0.5 + sin(clock * 3.0) * 0.3)


func animate_victory(delta: float) -> void:
	# Emote-ul de victorie: ambele brațe ridicate drept deasupra capului,
	# încheieturile apropiate, palmele spre înainte. Poziție serioasă, dramatică.
	rotation.z = 0.0
	rotation.x = lerpf(rotation.x, -0.08, delta * 4.0)
	root.position.y = 0.05 + sin(clock * 1.6) * 0.02
	var breathe := sin(clock * 1.6) * 0.015
	# umerii mutați în lateral, ca brațele ridicate să nu treacă prin ochii mari
	left_arm.position = Vector3(-1.02, 0.15, -0.15)
	right_arm.position = Vector3(1.02, 0.15, -0.15)
	left_arm.rotation = Vector3(0.05, 0, 2.74 + breathe)
	right_arm.rotation = Vector3(0.05, 0, -2.74 - breathe)
	# brațe mai lungi și mai groase
	left_arm.scale = Vector3(1.6, 2.95, 1.6)
	right_arm.scale = Vector3(1.6, 2.95, 1.6)
	for hand in hands:
		# anulăm întinderea brațului pentru mână, apoi o facem mare
		hand.scale = Vector3(1.0 / 1.6, 1.0 / 2.95, 1.0 / 1.6) * 1.9


func animate_sad(delta: float) -> void:
	rotation.x = lerpf(rotation.x, 0.4, delta * 2.0)   # capul plecat
	rotation.z = sin(clock * 1.4) * 0.18
	root.position.y = -0.2 + sin(clock * 1.4) * 0.05
	left_arm.rotation = Vector3(0.1, 0, -0.12)
	right_arm.rotation = Vector3(0.1, 0, 0.12)
