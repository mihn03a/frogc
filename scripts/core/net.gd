extends Node
## =====================================================================
##  NET.GD - multiplayer în rețeaua locală (autoload: Net)
## =====================================================================
##  Un jucător face HOST (serverul, are mereu id-ul 1), iar până la alți 3
##  dau JOIN scriind IP-ul host-ului. Folosim multiplayer-ul Godot (ENet),
##  pe portul 7777 (UDP).
##
##  Pașii:  Lobby -> host() / join() -> lista de jucători se sincronizează
##          -> host-ul apasă START -> toți încarcă arena de luptă.
##
##  RPC = "Remote Procedure Call": o funcție apelată pe ALT calculator.
##  @rpc de deasupra funcției spune cine are voie s-o apeleze și cum.
## =====================================================================

signal players_changed
signal connected
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal peer_left(peer_id: int)

const PORT := 7777
const MAX_PLAYERS := 4

var players := {}           # id jucător -> {"name": nume, "color": numărul culorii}
var my_name := "Frog"
var fill_bots := true       # completăm locurile goale cu boți?
var active := false         # suntem conectați (ca host sau client)?
var match_running := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(on_player_connected)
	multiplayer.peer_disconnected.connect(on_player_disconnected)
	multiplayer.connected_to_server.connect(on_connected_to_host)
	multiplayer.connection_failed.connect(on_connection_failed)
	multiplayer.server_disconnected.connect(on_host_disconnected)


# =====================================================================
#  FUNCȚII FOLOSITE DE LOBBY ȘI ARENĂ
# =====================================================================
func host(name_text: String) -> Error:
	leave()
	my_name = clean_name(name_text)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS - 1)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	active = true
	players = {1: {"name": my_name, "color": 0}}
	players_changed.emit()
	return OK


func join(ip: String, name_text: String) -> Error:
	leave()
	my_name = clean_name(name_text)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip.strip_edges(), PORT)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	active = true
	return OK


func leave() -> void:
	match_running = false
	if active and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {}
	active = false


func is_host() -> bool:
	return active and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id()


func start_match() -> void:
	if not is_host():
		return
	match_running = true
	start_on_everyone.rpc(fill_bots)


## Adresele IPv4 ale acestui calculator, pe care le pot scrie ceilalți jucători.
func local_ips() -> Array:
	var result := []
	for address in IP.get_local_addresses():
		var text := str(address)
		var is_ipv4 := text.count(".") == 3
		var is_useless := text.begins_with("127.") or text.begins_with("169.254.")
		if is_ipv4 and not is_useless:
			result.append(text)
	return result


# =====================================================================
#  EVENIMENTE DE REȚEA
# =====================================================================
func on_player_connected(id: int) -> void:
	# Host-ul refuză jucătorii în plus și pe cei care vin după start.
	if multiplayer.is_server() and (players.size() >= MAX_PLAYERS or match_running):
		var server := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		server.disconnect_peer(id)


func on_player_disconnected(id: int) -> void:
	peer_left.emit(id)
	if multiplayer.is_server() and players.has(id):
		players.erase(id)
		sync_players.rpc(players)


func on_connected_to_host() -> void:
	register_player.rpc_id(1, my_name)   # îi spunem host-ului cum ne cheamă
	connected.emit()


func on_connection_failed() -> void:
	leave()
	connection_failed.emit("Could not connect. Check the IP and that the host is waiting in the lobby.")


func on_host_disconnected() -> void:
	var was_in_match := match_running
	leave()
	if was_in_match:
		disconnected.emit("The host left the game.")
	else:
		disconnected.emit("Disconnected from the host.")


# =====================================================================
#  RPC-URI
# =====================================================================
## Un client nou se înscrie la host. Host-ul îi dă prima culoare liberă.
@rpc("any_peer", "call_remote", "reliable")
func register_player(name_text: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = {"name": clean_name(name_text), "color": first_free_color()}
	sync_players.rpc(players)


func first_free_color() -> int:
	var used := []
	for player in players.values():
		used.append(int(player["color"]))
	var color := 0
	while color in used:
		color += 1
	return color


## Host-ul trimite lista de jucători tuturor.
@rpc("authority", "call_local", "reliable")
func sync_players(new_list: Dictionary) -> void:
	players = new_list
	players_changed.emit()


## Host-ul pornește meciul pe toate calculatoarele deodată.
@rpc("authority", "call_local", "reliable")
func start_on_everyone(bots: bool) -> void:
	fill_bots = bots
	match_running = true
	GameState.change_scene(GameState.BATTLE_SCENE)


func clean_name(text: String) -> String:
	var name_text := text.strip_edges().substr(0, 12)
	if name_text == "":
		return "Frog"
	return name_text
