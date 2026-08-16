extends Node

const DEFAULT_PORT = 1337
const MAX_CLIENTS = 32

var players = {} 
var local_player_data = {"name": "Guest", "color": Color.WHITE, "x": 250, "y": 50}
var current_world = null 

func _ready():
	get_tree().set_auto_accept_quit(false)
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	if DisplayServer.get_name() == "headless":
		print("[Server] Headless mode detected. Starting Persistent Brain...")
		start_host()

# UI 

func show_loading(text: String):
	var overlay = get_tree().root.find_child("LoadingOverlay", true, false)
	if overlay:
		overlay.show()
		var label = overlay.find_child("Label", true, false)
		if label: label.text = text

func hide_loading():
	var overlay = get_tree().root.find_child("LoadingOverlay", true, false)
	if overlay: overlay.hide()

@rpc("any_peer", "call_local", "reliable")
func send_system_message(message: String):
	var chat = get_tree().root.find_child("ChatLog", true, false)
	if chat:
		chat.append_text("[color=yellow][b][SYSTEM]:[/b] " + message + "[/color]\n")

# WEB AUTOMATION 

func process_web_launch():
	if DisplayServer.get_name() == "headless": return
	
	var args = OS.get_cmdline_args()
	var user_args = OS.get_cmdline_user_args()
	var all_args = args + user_args
	var web_link = ""
	
	for arg in all_args:
		if arg.begins_with("pixgate://"):
			web_link = arg
			break
	
	if web_link == "": return 

	var clean_link = web_link.replace("pixgate://", "").trim_suffix("/")
	var action = ""; var username = ""; var ip = "127.0.0.1"
	var params = clean_link.split("&")
	for p in params:
		if "action=" in p: action = p.split("=")[1]
		if "user=" in p: username = p.split("=")[1]
		if "ip=" in p: ip = p.split("=")[1]

	if username != "":
		fetch_and_launch(username, action, ip)

func fetch_and_launch(username, action, ip):
	show_loading("Fetching Profile...")
	var http = HTTPRequest.new()
	add_child(http)
	
	http.request_completed.connect(func(_res, code, _headers, body):
		if code == 200:
			var json = JSON.parse_string(body.get_string_from_utf8())
			if json:
				local_player_data.name = json.username
				local_player_data.color = Color.from_string(json.color, Color.WHITE)
				if json.has("last_x"): local_player_data.x = json.last_x
				if json.has("last_y"): local_player_data.y = json.last_y
				
				if action == "host": start_host()
				elif action == "join": start_join(ip)
		else:
			hide_loading()
			print("[DEBUG] API Failure. Code: ", code)
	)
	http.request("http://localhost:3000/api/player/" + username)

# NETWORKING

func start_host():
	show_loading("Opening Portal...")
	
	# Try to auto-open the router ports
	var upnp = UPNP.new()
	var upnp_status = "Local Only"
	if upnp.discover() == UPNP.UPNP_RESULT_SUCCESS:
		if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
			var map_err = upnp.add_port_mapping(DEFAULT_PORT, DEFAULT_PORT, "Pixgate", "UDP")
			if map_err == UPNP.UPNP_RESULT_SUCCESS:
				upnp_status = "Public (UPNP)"
				print("[Network] SUCCESS: World is now public @ ", upnp.query_external_address())

	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(DEFAULT_PORT, MAX_CLIENTS)
	if err != OK:
		print("[Network] Failed to start server!")
		return
		
	multiplayer.multiplayer_peer = peer
	
	if DisplayServer.get_name() != "headless":
		players[1] = local_player_data
		nuke_menu()
		hide_loading()
		send_system_message("Universe Created. Mode: " + upnp_status)
	
	if current_world: current_world.auto_host()

func start_join(ip):
	show_loading("Connecting to " + ip + "...")
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, DEFAULT_PORT)
	if err != OK:
		show_loading("Connection Failed!")
		await get_tree().create_timer(2.0).timeout
		hide_loading()
		return
		
	multiplayer.multiplayer_peer = peer
	nuke_menu()

func nuke_menu():
	var canvas = get_tree().root.find_child("CanvasLayer", true, false)
	if canvas:
		var menu = canvas.get_node_or_null("MainMenu")
		var ui = canvas.get_node_or_null("IngameUI")
		if menu: menu.hide()
		if ui: ui.show()

# PERSISTENCE 

func save_player_to_db(player_id):
	if not multiplayer.is_server(): return
	if not players.has(player_id): return
	
	var player_node = get_tree().root.find_child(str(player_id), true, false)
	if player_node:
		var pos = player_node.global_position
		var http = HTTPRequest.new()
		add_child(http)
		var body = JSON.stringify({
			"username": players[player_id].name,
			"x": pos.x,
			"y": pos.y
		})
		http.request("http://localhost:3000/api/save-player", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

# MULTIPLAYER LOGIC 

func _on_player_connected(id):
	if id == 1: return 

	if multiplayer.is_server():
		for existing_id in players:
			sync_player_data.rpc_id(id, existing_id, players[existing_id])
		if DisplayServer.get_name() != "headless":
			sync_player_data.rpc(multiplayer.get_unique_id(), local_player_data)

@rpc("any_peer", "call_local", "reliable")
func sync_player_data(id, data):
	if id == 1: return
	
	var is_new_player = not players.has(id)
	players[id] = data
	update_player_visuals(id, data.name, data.color)
	update_player_list_ui()
	
	if is_new_player:
		send_system_message(data.name + " joined the universe.")
	
	if id == multiplayer.get_unique_id():
		hide_loading()

func _on_player_disconnected(id):
	if players.has(id):
		send_system_message(players[id].name + " left the universe.")
		save_player_to_db(id)
		players.erase(id)
	
	var player_node = get_tree().root.find_child(str(id), true, false)
	if player_node: player_node.queue_free()
	update_player_list_ui()

func _on_server_disconnected():
	players.clear()
	show_loading("The Host has shut down the server!")
	await get_tree().create_timer(3.0).timeout
	get_tree().quit() 

@rpc("any_peer", "call_local", "reliable")
func send_chat_message(sender_id, message):
	var sn = players[sender_id].name if players.has(sender_id) else "Server"
	var sc = players[sender_id].color if players.has(sender_id) else Color.YELLOW
	var chat = get_tree().root.find_child("ChatLog", true, false)
	if chat:
		chat.append_text("[color=#" + sc.to_html(false) + "][b]" + sn + ":[/b][/color] " + message + "\n")

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if multiplayer.multiplayer_peer:
			if multiplayer.is_server():
				for id in players: save_player_to_db(id)
				if DisplayServer.get_name() != "headless":
					var http = HTTPRequest.new(); add_child(http)
					var body = JSON.stringify({"username": local_player_data.name})
					http.request("http://localhost:3000/api/stop-hosting", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
					await get_tree().create_timer(0.4).timeout
		get_tree().quit()

func update_player_visuals(id, n, c):
	if id == 1: return
	await get_tree().create_timer(0.2).timeout
	var p = get_tree().root.find_child(str(id), true, false)
	if p:
		var lbl = p.find_child("Label", true, false)
		if lbl: 
			lbl.text = n
			lbl.add_theme_color_override("font_color", c)
		var r = p.find_child("ColorRect", true, false)
		if r: r.color = c

func update_player_list_ui():
	var list = get_tree().root.find_child("PlayerList", true, false)
	if list and list is ItemList:
		list.clear()
		for id in players:
			var idx = list.add_item(players[id].name)
			list.set_item_custom_fg_color(idx, players[id].color)
