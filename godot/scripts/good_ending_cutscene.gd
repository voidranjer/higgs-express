extends Sprite2D

# You can adjust this value in the Inspector to change how fast the sprite fades in.
@export var fade_speed = 0.05

# This variable is used to ensure we only set the opacity once.
var has_faded_in = false

# Called when the node enters the scene tree for the first time.
# We'll set the initial state of the sprite here.
func _ready():
	# Start with 0% opacity (fully transparent).
	# The 'a' component of the modulate property controls the alpha/opacity.
	modulate.a = 0.0


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	# We only need to run this code if the sprite hasn't faded in yet.
	if not has_faded_in:
		# Check the global game state.
		# This assumes you have an autoloaded singleton script named "GameState".
		if GameState.is_game_over_good_ending:
			# If the good ending is triggered, smoothly fade in the sprite.
			# We increase the alpha value over time, multiplied by delta
			# to make the animation frame-rate independent.
			modulate.a += fade_speed * delta
			
			# Once the alpha is 1.0 or more, the fade is complete.
			if modulate.a >= 1.0:
				# Clamp the value to 1.0 to prevent it from going over.
				modulate.a = 1.0
				# Set the flag to true so this code doesn't run again unnecessarily.
				has_faded_in = true
