extends Control

# Server configuration
const SERVER_URL = "ws://localhost:8765"
const BUFFER_LENGTH_SECONDS = 30.0

# Node references
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var connect_button: Button = $Button

# WebSocket and audio stream instances
var _ws_client = WebSocketPeer.new()
var _audio_stream_generator = AudioStreamGenerator.new()

# State variables
var _is_connected = false
var _has_received_header = false
var _is_stereo = false
var _sample_rate = 44100 # Default, will be overwritten by header
var _let_buffer_finish = false # New flag to let audio play out after disconnect


func _ready() -> void:
	# Assign the generator to the player, but don't configure it yet.
	# Configuration will happen after we receive the header from the server.
	audio_player.stream = _audio_stream_generator


func _process(delta: float) -> void:
	_ws_client.poll()
	var state = _ws_client.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not _is_connected:
			_on_connection_established()
		
		while _ws_client.get_available_packet_count() > 0:
			_process_packet()
			
	elif state == WebSocketPeer.STATE_CLOSED:
		if _is_connected:
			_on_connection_closed()
	
	# If the stream has ended, wait for the player to finish its buffer
	# before resetting the state for the next connection.
	if _let_buffer_finish and not audio_player.is_playing():
		print("Playback buffer finished. Resetting for next stream.")
		_let_buffer_finish = false
		_has_received_header = false


func _on_button_pressed() -> void:
	if _ws_client.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("Connecting to server...")
		# Reset state variables before attempting a new connection
		_let_buffer_finish = false
		_has_received_header = false
		var err = _ws_client.connect_to_url(SERVER_URL)
		if err != OK:
			print("Error connecting to server.")
	else:
		print("Disconnecting from server (user action)...")
		# Stop playback immediately because this is a user action
		_let_buffer_finish = false
		audio_player.stop()
		_ws_client.close(1000, "User requested disconnect")


func _on_connection_established() -> void:
	print("Connection established! Waiting for audio header...")
	_is_connected = true
	connect_button.text = "Disconnect"


func _on_connection_closed() -> void:
	print("Connection closed.")
	
	# If we had received the audio header, this was a graceful close from the server.
	# Set the flag to let the remaining audio in the buffer play out.
	if _has_received_header:
		print("Server closed connection. Letting audio buffer play out...")
		_let_buffer_finish = true
	
	_is_connected = false
	connect_button.text = "Connect"
	# IMPORTANT: Do not call audio_player.stop() here anymore.


func _process_packet() -> void:
	var packet: PackedByteArray = _ws_client.get_packet()
	
	if not _has_received_header:
		# The first packet is the JSON metadata header.
		var json_string = packet.get_string_from_utf8()
		var json = JSON.parse_string(json_string)
		
		if json == null:
			print("Error: Failed to parse metadata header.")
			_ws_client.close()
			return
		
		var metadata: Dictionary = json
		
		# Configure the audio stream based on the received header
		_sample_rate = metadata.get("sample_rate", 44100)
		_is_stereo = metadata.get("channels", 1) == 2
		
		# I increased the buffer length as you suggested
		_audio_stream_generator.mix_rate = _sample_rate
		_audio_stream_generator.buffer_length = BUFFER_LENGTH_SECONDS
		
		print("Received audio header: Sample Rate=", _sample_rate, ", Is Stereo=", _is_stereo)
		
		_has_received_header = true
		audio_player.play() # Start playing now that we are configured
	else:
		# Subsequent packets are raw audio data.
		_push_audio_data(packet)


func _push_audio_data(packet: PackedByteArray) -> void:
	# Convert 16-bit PCM audio data into PackedVector2Array for the generator.
	if packet.size() == 0:
		return
		
	var frames = PackedVector2Array()
	var playback: AudioStreamGeneratorPlayback = audio_player.get_stream_playback()
	
	if playback == null:
		return

	if _is_stereo:
		# 4 bytes per frame (16-bit stereo)
		frames.resize(packet.size() / 4)
		for i in range(frames.size()):
			var left_sample_int = packet.decode_s16(i * 4)
			var right_sample_int = packet.decode_s16(i * 4 + 2)
			var left_float = float(left_sample_int) / 32768.0
			var right_float = float(right_sample_int) / 32768.0
			frames[i] = Vector2(left_float, right_float)
	else: # Mono
		# 2 bytes per frame (16-bit mono)
		frames.resize(packet.size() / 2)
		for i in range(frames.size()):
			var sample_int = packet.decode_s16(i * 2)
			var sample_float = float(sample_int) / 32768.0
			# For mono, both left and right channels get the same sample
			frames[i] = Vector2(sample_float, sample_float)
			
	playback.push_buffer(frames)
