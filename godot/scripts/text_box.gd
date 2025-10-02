# Textbox.gd
class_name Textbox
extends PanelContainer

# This signal will be emitted when the player presses Enter.
# The main game script will listen for this.
signal text_submitted(text)

# Get references to our nodes
@onready var character_name_label: Label = $VBoxContainer/HBoxContainer/CharacterName
@onready var input_box: LineEdit = $VBoxContainer/InputBox
@onready var cancel_button: Button = $VBoxContainer/HBoxContainer/CancelButton


func _ready() -> void:
	# Hide the textbox by default when the game starts.
	hide()
	# Connect the LineEdit's built-in signal to our function.
	# This signal fires automatically when the user presses Enter.
	input_box.text_submitted.connect(_on_input_box_text_submitted)
	
	# Cancel button
	cancel_button.pressed.connect(
		func(): _on_input_box_text_submitted("")
	)
	

# This function shows the textbox and prepares it for input.
func start_chat(character_name: String) -> void:
	character_name_label.text = character_name
	show() # Make the textbox visible.
	input_box.clear() # Clear any previous text.
	input_box.grab_focus() # <-- This is the autofocus magic!

# This function is called when the 'text_submitted' signal from the LineEdit is fired.
func _on_input_box_text_submitted(player_text: String) -> void:
	# Ignore empty submissions.
	#if player_text.strip_edges().is_empty():
		#return
	
	# Emit our own custom signal with the player's text.
	text_submitted.emit(player_text)
	
	# Clean up and hide the box.
	input_box.clear()
	hide()
