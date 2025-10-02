# HiggsApiStreamer.gd
# A Godot 4 Node that streams text-to-speech audio using HttpClient.
# It creates an AudioStreamPlayer2D dynamically to play the audio as it arrives.
class_name HiggsAudioStreamer
extends Node2D

# The URL for the text-to-speech API endpoint.
# const TTS_API_URL = "http://45.67.213.138:20023/v1/audio/speech"
#const TTS_API_URL = "http://localhost:8000/v1/audio/speech"

# The host and port are derived from the URL for HttpClient.
const TTS_HOST = "localhost"
const TTS_PORT = 443
const TTS_PATH = "/higgs"

# The HttpClient is used for low-level, non-blocking network communication.
var http_client = HTTPClient.new()

# These will be created dynamically when 'speak()' is called.
var audio_player: AudioStreamPlayer2D
var audio_playback: AudioStreamGeneratorPlayback

# Intermediate buffer to hold audio frames received from the network
# before they are pushed to the audio player.
var frame_buffer = PackedVector2Array()

# State flags to manage the streaming process.
var is_streaming = false
var response_code_checked = false

# Emitted when the audio finishes playing and the player is cleaned up.
signal finished_playing_audio()


# The _process function is called every frame. It handles both polling the
# network for new data and servicing the audio player's buffer.
func _process(_delta):
	# This section handles polling the network for new audio data.
	# It only runs while the connection is active.
	if is_streaming:
		http_client.poll()
		var status = http_client.get_status()

		if status == HTTPClient.STATUS_BODY:
			# On first entering BODY state, check the response code to ensure success.
			if not response_code_checked:
				var response_code = http_client.get_response_code()
				print("DEBUG: HTTP Response Code: ", response_code)
				
				if response_code != 200:
					print_rich("[color=red]Request failed with HTTP status: %d[/color]" % response_code)
					var error_chunk = http_client.read_response_body_chunk()
					if error_chunk.size() > 0:
						print_rich("[color=red]Error message: %s[/color]" % error_chunk.get_string_from_utf8())
					
					http_client.close()
					is_streaming = false
					_cleanup_player()
					return
				
				response_code_checked = true

			# Read a chunk from the response body and add it to our frame buffer.
			var chunk = http_client.read_response_body_chunk()
			if chunk.size() > 0:
				_convert_chunk_to_frames(chunk)

		elif status == HTTPClient.STATUS_DISCONNECTED or status == HTTPClient.STATUS_CONNECTION_ERROR or status == HTTPClient.STATUS_CANT_CONNECT:
			print("HiggsApiStreamer: Connection closed or failed. Status: ", status)
			is_streaming = false # Stop polling the network
			http_client.close()
			
	# This section services the audio player's buffer.
	# It runs independently of the network stream, as long as there is a valid
	# player and frames in our intermediate buffer to give it.
	if is_instance_valid(audio_player):
		if not frame_buffer.is_empty():
			_service_audio_buffer()
		else:
			# If our buffer is empty AND the stream is finished...
			if not is_streaming:
				# If the player is still 'playing' (i.e., starved), tell it to stop.
				if audio_player.is_playing():
					print("DEBUG: Stream ended and buffer is empty. Stopping player.")
					audio_player.stop()
				# Otherwise, if it has been stopped, clean it up.
				else:
					print("DEBUG: Player stopped. Cleaning up.")
					_cleanup_player()

# This function initiates the text-to-speech request and prepares for streaming.
func speak(text_to_speak: String, voice: String):
	print("DEBUG: speak() called with text: '", text_to_speak, "', voice: '", voice, "'")
	
	# Reset state for the new request.
	response_code_checked = false
	frame_buffer.clear()

	if is_streaming:
		print("DEBUG: A stream is already active. Closing it before starting a new one.")
		http_client.close()
		is_streaming = false
	
	if is_instance_valid(audio_player):
		print("DEBUG: Cleaning up a previous audio player instance.")
		audio_player.queue_free()
		audio_player = null
		audio_playback = null
		
	# 1. Prepare the Audio Player and Stream Generator
	var audio_stream_generator = AudioStreamGenerator.new()
	audio_stream_generator.mix_rate = 24000
	audio_stream_generator.buffer_length = 0.5 # A reasonable buffer length.
	
	audio_player = AudioStreamPlayer2D.new()
	add_child(audio_player)
	audio_player.stream = audio_stream_generator
	audio_player.max_distance = 250 # px. should be scaled based on map size
	audio_player.bus = "Character Dialogue"
	
	audio_player.play()
	print("DEBUG: Audio player started. play() called.")
	
	audio_playback = audio_player.get_stream_playback()
	if not audio_playback:
		print_rich("[color=red]DEBUG: Failed to get audio_playback after calling play()![/color]")
		_cleanup_player()
		return
	
	# 2. Make the HTTP Request using HttpClient
	print("DEBUG: Connecting to host ", TTS_HOST, ":", TTS_PORT)
	var tls_options = TLSOptions.client_unsafe()
	var error = http_client.connect_to_host(TTS_HOST, TTS_PORT, tls_options)
	if error != OK:
		print_rich("[color=red]Could not connect to host.[/color]")
		_cleanup_player()
		return

	is_streaming = true

	while http_client.get_status() == HTTPClient.STATUS_CONNECTING or http_client.get_status() == HTTPClient.STATUS_RESOLVING:
		http_client.poll()
		await get_tree().process_frame

	if http_client.get_status() != HTTPClient.STATUS_CONNECTED:
		print_rich("[color=red]Failed to connect after waiting.[/color]")
		_cleanup_player()
		return
	
	print("DEBUG: Connection successful.")
		
	var body_dict = {
		"model": "higgs-audio-v2-generation-3B-base",
		"voice": voice,
		"input": text_to_speak,
		"response_format": "pcm"
	}
	var body_json_string = JSON.stringify(body_dict)
	var headers = [
		"Content-Type: application/json",
		"Host: %s" % TTS_HOST
	]

	print("DEBUG: Sending request to path: ", TTS_PATH)
	error = http_client.request(HTTPClient.METHOD_POST, TTS_PATH, headers, body_json_string)
	if error != OK:
		print_rich("[color=red]Error making HTTP request.[/color]")
		_cleanup_player()


# Converts a raw byte chunk into audio frames and adds them to our intermediate buffer.
func _convert_chunk_to_frames(byte_array: PackedByteArray):
	var frame_count = byte_array.size() / 2 # Use / for float division, then it's cast to int anyway. It avoids the warning.
	if frame_count == 0:
		return
		
	var start_index = frame_buffer.size()
	frame_buffer.resize(start_index + frame_count)

	for i in range(frame_count):
		var sample_s16 = byte_array.decode_s16(i * 2)
		var sample_float = float(sample_s16) / 32768.0
		frame_buffer[start_index + i] = Vector2(sample_float, sample_float)
	
	#print("DEBUG: Converted and queued ", frame_count, " frames. Total in queue: ", frame_buffer.size())


# Moves frames from our intermediate buffer to the audio player's buffer.
func _service_audio_buffer():
	if not is_instance_valid(audio_playback) or frame_buffer.is_empty():
		return
		
	# get_frames_available() returns the amount of free space in the player's buffer.
	var space_in_player = audio_playback.get_frames_available()
	
	if space_in_player > 0:
		# Decide how many frames to push: either all the available space, or whatever we have in our buffer.
		var frames_to_push_count = min(space_in_player, frame_buffer.size())
		
		if frames_to_push_count > 0:
			var frames_to_push = frame_buffer.slice(0, frames_to_push_count)
			audio_playback.push_buffer(frames_to_push)
			# Remove the pushed frames from our intermediate buffer.
			frame_buffer = frame_buffer.slice(frames_to_push_count)
			#print("DEBUG: Pushed ", frames_to_push_count, " frames to player. ", frame_buffer.size(), " frames remaining in queue.")

# Helper function to consolidate cleanup logic.
func _cleanup_player():
	print("DEBUG: _cleanup_player called.")
	if is_instance_valid(audio_player):
		audio_player.queue_free()
	audio_player = null
	audio_playback = null
	is_streaming = false
	frame_buffer.clear() # Clear our own buffer as well
	finished_playing_audio.emit()
