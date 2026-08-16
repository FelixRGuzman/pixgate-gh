extends CharacterBody2D

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

# Network sync variable
@export var sync_position: Vector2

func _enter_tree():
	# Set authority based on the node name (the network ID)
	set_multiplayer_authority(name.to_int())

func _ready():
	# Sets initial label to ID
	var name_label = get_node_or_null("ColorRect/Label")
	if name_label:
		name_label.text = str(name)
	
	# Send our data to the server via handshake
	if is_multiplayer_authority():
		GameManager.sync_player_data.rpc(multiplayer.get_unique_id(), GameManager.local_player_data)

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		# If any UI is focused, stop movement.
		if get_viewport().gui_get_focus_owner() != null:
			velocity.x = 0
			if not is_on_floor():
				velocity += get_gravity() * delta
			move_and_slide()
			sync_position = global_position
			return 

		# MOVEMENT
		if not is_on_floor():
			velocity += get_gravity() * delta

		if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
			velocity.y = JUMP_VELOCITY

		# Simplified direction check
		var direction = Input.get_axis("ui_left", "ui_right")
		if direction == 0: # Fallback for raw keys if UI actions aren't set
			if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): direction -= 1
			if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): direction += 1
			
		velocity.x = direction * SPEED
		move_and_slide()
		
		# Ball Physics
		for i in get_slide_collision_count():
			var collision = get_slide_collision(i)
			if collision.get_collider() is RigidBody2D:
				collision.get_collider().apply_central_impulse(-collision.get_normal() * 400.0)

		sync_position = global_position
	else:
		# Interpolate sync/global position so players don't teleport
		global_position = global_position.lerp(sync_position, 0.5)
