class_name Character
extends Node2D

@onready var label: Label = $Label
@onready var text_box: Textbox = $TextBox
#@onready var higgs_player: HiggsPlayer = $HiggsPlayer
@onready var higgs_player: HiggsAudioStreamer = $HiggsAudioStreamer
@onready var llm_api: Node = $LlmApi
@onready var chat_bubble: Sprite2D = $ChatBubble

# Configuration

# State variables
@export var character_name = "walter"
@export var is_interacting: bool = false

func _ready():
	# "E" label
	hide_e_prompt()
	label.self_modulate.a = 0.0
	
	# Textbox
	text_box.text_submitted.connect(_on_player_response)
	
	# Audio
	higgs_player.finished_playing_audio.connect(_on_finish_playing_audio)
	
	# LLM
	llm_api.character_name = character_name
	llm_api.character_response_received.connect(
		func(character_response: String): higgs_player.speak(character_response, character_name)
	)
	
func _process(_delta: float):
	chat_bubble.visible = is_interacting

func _on_finish_playing_audio():
	is_interacting = false
	show_e_prompt()

func interact():
	if is_interacting:
		return
	is_interacting = true
	hide_e_prompt()
	text_box.start_chat(character_name)

func _on_player_response(response: String) -> void:
	if response.strip_edges().is_empty():
		_on_finish_playing_audio()
		return

	var char_response = await llm_api.talk_to_char(response)

func show_e_prompt():
	#label.visible = true
	var tween = create_tween()
	tween.tween_property(label, "self_modulate:a", 1.0, 0.2) # Fade to alpha 1.0 over 0.2s
	
func hide_e_prompt():
	#label.visible = false
	var tween = create_tween()
	tween.tween_property(label, "self_modulate:a", 0.0, 0.2) # Fade to alpha 0.0 over 0.2s
