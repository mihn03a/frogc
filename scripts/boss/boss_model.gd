extends Node3D
## =====================================================================
##  BOSS_MODEL.GD - cum arată "The Big Nic"
## =====================================================================
##  Un broscoi uriaș cu coroană și pelerină, construit din forme simple
##  (sfere, cutii, cilindri). Privește spre -Z.
##
##  Fața: în loc de ochi și gură, poartă fața unui prieten
##  (assets/textures/boss_face.png) pe o mască curbată, sub coroană.
##  Dacă poza lipsește, primește înapoi ochii și gura de broscoi.
##
##  Stări de spirit (mood): "angry", "hurt", "dizzy", "cry".
##  Fiecare schimbă fața (culoare, înclinare) sau ochii și gura, plus mișcarea.
## =====================================================================

const SKIN := Color(0.28, 0.5, 0.2)
const USE_FRIEND_FACE := true                    # false = ochii și gura de broscoi
const FACE_TEXTURE_PATH := "res://assets/textures/boss_face.png"
const FACE_SIZE := 3.3                           # lățimea măștii cu fața
const FACE_CENTER := Vector3(0, 1.05, -2.6)      # în fața corpului, sub coroană
const TEAR_SPOTS := [Vector3(-0.45, 0.9, -2.85), Vector3(0.45, 0.9, -2.85)]   # sub ochii din poză

var mood := "angry"
var clock := 0.0
var flash_time := 0.0          # cât mai stă alb după o lovitură
var body_mesh: MeshInstance3D
var skin_material: StandardMaterial3D
var white_material: StandardMaterial3D
var root: Node3D               # tot corpul (îl mișcăm pentru animații)
var brows: Array[Node3D] = []
var pupils: Array[Node3D] = []
var mouth: Node3D
var left_arm: Node3D
var right_arm: Node3D
var tears: Array[GPUParticles3D] = []
var dizzy_stars: Node3D
var face_mask: MeshInstance3D      # masca cu fața prietenului (null dacă nu e folosită)
var face_material: StandardMaterial3D
var face_tint := Color(1, 1, 1)    # culoarea feței pentru starea de acum


# =====================================================================
#  CONSTRUCȚIA MODELULUI
# =====================================================================
func _ready() -> void:
	root = Node3D.new()
	add_child(root)
	skin_material = FX.mat(SKIN, 0.0, 0.0, 0.6)
	white_material = FX.mat(Color(1, 1, 1), 2.0)
	build_cape()
	build_body()
	var friend_face: Texture2D = null
	if USE_FRIEND_FACE:
		friend_face = FX.load_texture_file(FACE_TEXTURE_PATH)
	if friend_face:
		build_friend_face(friend_face)
	else:
		for side in [-1.0, 1.0]:
			build_eye(side)
		build_mouth()
	build_crown()
	for side in [-1.0, 1.0]:
		build_arm(side)
	build_hover_pod()
	build_dizzy_stars()
	set_mood("angry")


func build_cape() -> void:
	var red := FX.mat(Color(0.75, 0.08, 0.12), 0.0, 0.0, 0.5)
	FX.add_mesh(root, FX.box_mesh(Vector3(4.6, 4.2, 0.18)), red, Vector3(0, -0.4, 2.1), Vector3(0.25, 0, 0))
	FX.add_mesh(root, FX.box_mesh(Vector3(4.8, 0.5, 0.6)), FX.mat(Color(0.95, 0.95, 0.95)), Vector3(0, 1.3, 1.6))


func build_body() -> void:
	body_mesh = FX.add_mesh(root, FX.sphere_mesh(1.0, 18), skin_material, Vector3.ZERO, Vector3.ZERO, Vector3(2.6, 2.1, 2.4))
	var belly := FX.mat(Color(0.85, 0.8, 0.45))
	FX.add_mesh(root, FX.sphere_mesh(1.0, 14), belly, Vector3(0, -0.6, -0.9), Vector3.ZERO, Vector3(2.0, 1.4, 1.5))
	# negi pe spate (seed fix = mereu aceiași negi)
	var wart := FX.mat(SKIN.darkened(0.35))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 14:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1), rng.randf_range(-0.2, 1)).normalized()
		FX.add_mesh(root, FX.sphere_mesh(rng.randf_range(0.12, 0.25), 6), wart, Vector3(dir.x * 2.55, dir.y * 2.05, dir.z * 2.35))


func build_eye(side: float) -> void:
	FX.add_mesh(root, FX.sphere_mesh(0.8, 14), skin_material, Vector3(side * 1.2, 1.6, -1.2))
	FX.add_mesh(root, FX.sphere_mesh(0.7, 14), FX.mat(Color(1, 1, 0.9)), Vector3(side * 1.22, 1.7, -1.42))
	# pupila (iris portocaliu + fantă neagră)
	var pupil := Node3D.new()
	pupil.position = Vector3(side * 1.25, 1.72, -2.05)
	root.add_child(pupil)
	FX.add_mesh(pupil, FX.sphere_mesh(0.34, 12), FX.mat(Color(1.0, 0.55, 0.05), 0.8), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.4))
	FX.add_mesh(pupil, FX.box_mesh(Vector3(0.12, 0.5, 0.1)), FX.mat(Color(0.03, 0.03, 0.03)), Vector3(0, 0, -0.14))
	pupils.append(pupil)
	# sprânceana
	var brow := Node3D.new()
	brow.position = Vector3(side * 1.2, 2.45, -1.6)
	root.add_child(brow)
	FX.add_mesh(brow, FX.box_mesh(Vector3(1.2, 0.22, 0.3)), FX.mat(Color(0.12, 0.18, 0.08)))
	brows.append(brow)
	# lacrimile (pornesc doar când plânge)
	var tear := FX.make_emitter(Color(0.35, 0.7, 1.0), 40, 1.2, Vector3(side * 0.6, 0.6, -0.4), 25.0, 3.0, 5.0, Vector3(0, -14, 0), 0.35)
	tear.position = Vector3(side * 1.25, 1.4, -2.0)
	tear.emitting = false
	root.add_child(tear)
	tears.append(tear)


func build_mouth() -> void:
	mouth = Node3D.new()
	mouth.position = Vector3(0, 0.25, -2.25)
	root.add_child(mouth)
	FX.add_mesh(mouth, FX.box_mesh(Vector3(2.6, 0.18, 0.2)), FX.mat(Color(0.3, 0.05, 0.08)))


func build_friend_face(texture: Texture2D) -> void:
	face_mask = FX.make_face_mask(texture, FACE_SIZE, 3.5)
	face_material = face_mask.material_override
	face_mask.position = FACE_CENTER
	root.add_child(face_mask)
	for spot in TEAR_SPOTS:   # lacrimile curg de sub ochii din poză
		var side := signf(spot.x)
		var tear := FX.make_emitter(Color(0.35, 0.7, 1.0), 40, 1.2, Vector3(side * 0.6, 0.6, -0.4), 25.0, 3.0, 5.0, Vector3(0, -14, 0), 0.35)
		tear.position = spot
		tear.emitting = false
		root.add_child(tear)
		tears.append(tear)


func build_crown() -> void:
	var gold := FX.mat(Color(1.0, 0.78, 0.15), 0.3, 0.9, 0.25)
	var crown := Node3D.new()
	crown.position = Vector3(0, 2.25, 0.1)
	crown.rotation.x = -0.15
	root.add_child(crown)
	FX.add_mesh(crown, FX.cyl_mesh(0.95, 1.05, 0.6, 16), gold)
	for i in 6:   # 6 vârfuri, fiecare cu o piatră prețioasă
		var angle := i * TAU / 6.0
		FX.add_mesh(crown, FX.cyl_mesh(0.0, 0.22, 0.6, 6), gold, Vector3(cos(angle) * 0.9, 0.55, sin(angle) * 0.9))
		FX.add_mesh(crown, FX.sphere_mesh(0.12, 8), FX.mat(Color(1, 0.1, 0.3), 2.0), Vector3(cos(angle) * 1.02, 0.05, sin(angle) * 1.02))


func build_arm(side: float) -> void:
	var shoulder := Node3D.new()   # brațul se rotește în jurul umărului
	shoulder.position = Vector3(side * 2.3, 0.0, -0.6)
	root.add_child(shoulder)
	FX.add_mesh(shoulder, FX.capsule_mesh(0.35, 1.8), skin_material, Vector3(0, -0.8, 0))
	FX.add_mesh(shoulder, FX.sphere_mesh(0.48, 10), skin_material, Vector3(0, -1.7, 0), Vector3.ZERO, Vector3(1.2, 0.6, 1.2))
	if side < 0.0:
		left_arm = shoulder
	else:
		right_arm = shoulder


func build_hover_pod() -> void:
	# Inelul pe care plutește + flacăra de dedesubt.
	FX.add_mesh(self, FX.torus_mesh(2.0, 2.5, 32), FX.mat(Color(1.0, 0.2, 0.9), 3.0, 0.6, 0.3), Vector3(0, -2.3, 0))
	var thruster := FX.make_emitter(Color(1.0, 0.3, 0.9), 40, 0.5, Vector3.DOWN, 15.0, 4.0, 8.0, Vector3.ZERO, 0.45, Vector3(1.5, 0.1, 1.5))
	thruster.position = Vector3(0, -2.5, 0)
	add_child(thruster)
	thruster.emitting = true


func build_dizzy_stars() -> void:
	dizzy_stars = Node3D.new()
	dizzy_stars.position = Vector3(0, 3.6, 0)
	dizzy_stars.visible = false
	root.add_child(dizzy_stars)
	for i in 5:
		var angle := i * TAU / 5.0
		FX.add_mesh(dizzy_stars, FX.sphere_mesh(0.22, 6), FX.mat(Color(1, 1, 0.3), 3.0), Vector3(cos(angle) * 1.4, 0, sin(angle) * 1.4))


# =====================================================================
#  EXPRESII
# =====================================================================
func set_mood(new_mood: String) -> void:
	mood = new_mood
	var brow_angle := 0.0
	var mouth_scale := Vector3.ONE
	var pupil_scale := Vector3.ONE
	if new_mood == "angry":
		brow_angle = -0.45
	elif new_mood == "hurt":
		brow_angle = 0.35
		mouth_scale = Vector3(0.8, 4.0, 1)   # gura deschisă
		pupil_scale = Vector3(1, 0.3, 1)     # ochii strânși
	elif new_mood == "dizzy":
		brow_angle = 0.2
		mouth_scale = Vector3(0.6, 2.0, 1)
	elif new_mood == "cry":
		brow_angle = 0.55
		mouth_scale = Vector3(0.9, 6.0, 1)
		pupil_scale = Vector3(1, 0.25, 1)
	update_face_for_mood(new_mood)
	if brows.size() == 2:
		brows[0].rotation.z = brow_angle
		brows[1].rotation.z = -brow_angle
	if mouth:
		mouth.scale = mouth_scale
	for pupil in pupils:
		pupil.scale = pupil_scale
	for tear in tears:
		tear.emitting = (new_mood == "cry")
	if dizzy_stars:
		dizzy_stars.visible = (new_mood == "dizzy")


func update_face_for_mood(new_mood: String) -> void:
	# Poza nu-și poate schimba expresia, așa că o înclinăm și îi schimbăm culoarea.
	if face_mask == null:
		return
	var tilt := 0.0
	face_tint = Color(1, 1, 1)
	if new_mood == "angry":
		face_tint = Color(1.0, 0.85, 0.85)   # puțin roșu de nervi
		tilt = 0.06                          # se uită în jos, spre broască
	elif new_mood == "hurt":
		face_tint = Color(1.0, 0.55, 0.55)
	elif new_mood == "dizzy":
		face_tint = Color(0.85, 1.0, 0.8)    # verde de amețeală
	elif new_mood == "cry":
		face_tint = Color(0.8, 0.85, 1.0)
		tilt = -0.15                         # plânge cu capul pe spate
	face_mask.rotation.x = tilt
	if flash_time <= 0.0:
		face_material.albedo_color = face_tint


func hit_flash() -> void:
	# Devine alb o clipă când e lovit.
	flash_time = 0.12
	body_mesh.material_override = white_material
	if face_material:
		face_material.albedo_color = Color(2.5, 2.5, 2.5)   # și fața strălucește


func attack_pose() -> void:
	# Ridică brațele repede, apoi le coboară încet.
	if left_arm == null:
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(left_arm, "rotation:z", -2.2, 0.15)
	tween.tween_property(right_arm, "rotation:z", 2.2, 0.15)
	tween.chain().set_parallel(true)
	tween.tween_property(left_arm, "rotation:z", -0.2, 0.4)
	tween.tween_property(right_arm, "rotation:z", 0.2, 0.4)


# =====================================================================
#  ANIMAȚIE ÎN FIECARE CADRU
# =====================================================================
func _process(delta: float) -> void:
	clock += delta
	update_flash(delta)
	if mood == "angry":
		root.position.y = sin(clock * 2.0) * 0.15
		root.rotation.z = sin(clock * 1.3) * 0.05
	elif mood == "hurt":
		root.rotation.z = sin(clock * 30.0) * 0.08     # tremură
	elif mood == "dizzy":
		dizzy_stars.rotate_y(delta * 4.0)
		root.rotation.z = sin(clock * 3.0) * 0.2       # se clatină
	elif mood == "cry":
		animate_crying()


func update_flash(delta: float) -> void:
	if flash_time <= 0.0:
		return
	flash_time -= delta
	if flash_time <= 0.0:
		body_mesh.material_override = skin_material
		if face_material:
			face_material.albedo_color = face_tint


func animate_crying() -> void:
	# Plâns exagerat, comic: sare repede și își freacă ochii cu brațele.
	root.position.y = absf(sin(clock * 9.0)) * 0.35
	root.rotation.z = sin(clock * 5.0) * 0.08
	if mouth:
		mouth.scale.y = 5.0 + sin(clock * 18.0) * 1.5
	if face_mask:
		face_mask.scale = Vector3(1.0, 1.0 + sin(clock * 18.0) * 0.04, 1.0)   # suspină
	if left_arm:
		var rub := sin(clock * 12.0) * 0.25
		left_arm.rotation = Vector3(2.3, 0, 0.5 + rub)
		right_arm.rotation = Vector3(2.3, 0, -0.5 - rub)
