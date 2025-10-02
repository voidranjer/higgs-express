extends CharacterBody2D

@export var speed = 130.0
@export var jump_velocity = -300.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var target_interactable = null

func _process(delta):	
	if GameState.is_game_over_good_ending or GameState.is_game_over_bad_ending:
		set_physics_process(false)
		return
	
	# Check if we are near an interactable AND the "interact" button is pressed.
	if target_interactable and Input.is_action_just_pressed("interact") and not target_interactable.is_interacting:
		# Call the interact() function on the NPC's script.
		target_interactable.interact()

# This function is called when the player's InteractionRange enters another area.
func _on_interaction_range_area_entered(area):
	var target = area.get_parent()
	if target.is_in_group("interactables"):
		target_interactable = target
		if not target.is_interacting:
			target.show_e_prompt()

# This function is called when the player's InteractionRange exits another area.
func _on_interaction_range_area_exited(area):
	var target = area.get_parent()
	if target.is_in_group("interactables"):
		# If we are moving away from the interactable we were targeting, clear it.
		if target_interactable == target:
			target_interactable = null
			target.hide_e_prompt()

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

   	# A UI element is active, so don't process movement.
	if get_viewport().gui_get_focus_owner() != null:
		return 
	
	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("move_left", "move_right")
	if direction:
		velocity.x = direction * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		
	# Change direction
	if direction > 0:
		animated_sprite.flip_h = false
	elif direction < 0:
		animated_sprite.flip_h = true

	move_and_slide()
