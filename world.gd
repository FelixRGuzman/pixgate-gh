extends Node2D

@export var player_scene: PackedScene
@export var ball_scene: PackedScene 

func _ready():
	# Register this world so GameManager can find it
	GameManager.current_world = self
	
	# Tell it to check for deep links
	GameManager.process_web_launch()
	
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(add_player)
		
# These are called by GameManager ONLY when the website says so.

func auto_host():
	print("[World] Web command confirmed: Hosting...")
	spawn_ball()
	add_player(1) 

func auto_join():
	print("[World] Web command confirmed: Joining...")
	
	# Client is now waiting for the server to call 'add_player'

# CORE GAMEPLAY 

func spawn_ball():
	if not multiplayer.is_server(): return
	if $Players.has_node("WorldBall"): return 
	var ball = ball_scene.instantiate()
	ball.name = "WorldBall" 
	$Players.add_child(ball) 
	ball.position = Vector2(250, 100)

func add_player(id):
	if not multiplayer.is_server(): return
	if $Players.has_node(str(id)): return

	var player = player_scene.instantiate()
	player.name = str(id)
	$Players.add_child(player)
	player.set_multiplayer_authority(id)
	player.position = Vector2(randf_range(50, 450), 50)

# INPUT & CHAT 

func _input(event):
	var input_box = find_child("ChatInput", true, false)
	if not input_box: return 
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_SLASH:
		if not input_box.has_focus():
			input_box.grab_focus()
			get_viewport().set_input_as_handled() 

	if event.is_action_pressed("ui_accept"):
		if input_box.has_focus():
			if input_box.text != "":
				GameManager.send_chat_message.rpc(multiplayer.get_unique_id(), input_box.text)
				input_box.text = "" 
			input_box.release_focus()
			get_viewport().set_input_as_handled() 

# PHYSICS SYNC 

func _physics_process(_delta):
	# If there is no network, or the network is closing, STOP PHYSICS IMMEDIATELY
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if not multiplayer.is_server(): 
		return
	
	# Ball and player logic
	var ball = $Players.get_node_or_null("WorldBall")
	if ball and ball.position.y > 1000:
		ball.position = Vector2(250, 100)
		ball.linear_velocity = Vector2.ZERO
		
	for player in $Players.get_children():
		if player.name != "WorldBall" and player.position.y > 1000:
			player.position = Vector2(randf_range(50, 450), 50)
