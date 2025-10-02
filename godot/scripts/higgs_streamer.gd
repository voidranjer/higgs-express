# TTS_Player_Streamed.gd
# A Godot 4 Node that sends a text-to-speech request and streams the audio as it arrives.
# This version uses HTTPClient and AudioStreamGenerator for low-latency playback.
class_name HiggsStreamer
extends AudioStreamPlayer2D

# We use the lower-level HTTPClient to handle streaming responses chunk-by-chunk.
var http_client = HTTPClient.new()

# API connection details.
const HOST = "45.67.213.138"
#const HOST = "localhost"
const PORT = 20023
#const PORT = 8000
const API_PATH = "/v1/audio/speech"
const USE_SSL = false

# This signal is emitted when the audio stream has finished playing.
signal finished_playing_audio

# The AudioStreamGenerator lets us feed raw audio data into the player on the fly.
var audio_stream_generator: AudioStreamGenerator

# This is the object we interact with to push audio frames.
var audio_stream_generator_playback: AudioStreamGeneratorPlayback

# A buffer to hold incoming audio data before it's pushed to the player.
var pcm_buffer = PackedByteArray()

var _is_streaming = false
var _connection_closed = false
var _http_error_found = false # To track if we've already handled an error


# The _ready() function is called when the node enters the scene tree.
func _ready():
	# 1. Set up the AudioStreamGenerator.
	audio_stream_generator = AudioStreamGenerator.new()
	audio_stream_generator.mix_rate = 24000 # Matches the API's output sample rate.
	audio_stream_generator.buffer_length = 0.5 # A 0.5-second buffer is a good starting point.
	
	# 2. Assign the generator to this player.
	self.stream = audio_stream_generator
	
	# 3. Start playing. The player will now wait for data to be pushed into the buffer.
	play()
	
	# 4. Get the playback object, which we'll use to push frames.
	# We must call play() before we can get the stream playback.
	audio_stream_generator_playback = get_stream_playback()
	
	print("HiggsPlayerStreamed ready.")


# Ensure the connection is closed when the node is removed from the scene.
func _exit_tree():
	http_client.close()


# The _process function is called every frame. We use it to poll the HTTP client
# and feed new audio data to the player.
func _process(_delta):
	if not _is_streaming:
		return

	# Update the state of the HTTP client.
	http_client.poll()
	var status = http_client.get_status()

	# Check for non-200 response codes once headers are received.
	# We use a flag to ensure we only check this once per stream.
	if status >= HTTPClient.STATUS_BODY and not _http_error_found and http_client.has_response():
		var response_code = http_client.get_response_code()
		if response_code != 200:
			_http_error_found = true
			print_rich("[color=red]Request failed with HTTP status code: %d[/color]" % response_code)
			# Don't try to play the body, just stop the stream and signal completion.
			stop_stream()
			finished_playing_audio.emit()
			return

	# If the client is receiving the body of the response, read a chunk of it.
	if status == HTTPClient.STATUS_BODY:
		var chunk = http_client.read_response_body_chunk()
		if chunk.size() > 0:
			pcm_buffer.append_array(chunk)

	# Check if the server has finished sending data and closed the connection.
	if status == HTTPClient.STATUS_DISCONNECTED:
		_connection_closed = true
	print(status)
	
	# Now, push any data from our buffer into the audio generator.
	push_buffer_to_player()

	# --- Playback Completion Logic ---

	# If the connection is closed, our local buffer is empty, and we haven't already started a finish timer...
	if _connection_closed and pcm_buffer.size() < 2 and _is_streaming:
		# To avoid creating multiple timers, we check if a finish timer is already running
		# by checking for nodes in a specific group.
		var existing_timers = get_tree().get_nodes_in_group("higgs_finish_timer")
		if existing_timers.is_empty():
			# All audio data has been received and pushed to the generator's buffer.
			# Now, we wait for the generator's internal buffer to play out.
			# We'll use a one-shot timer slightly longer than the buffer length to be safe.
			var timer_duration = audio_stream_generator.buffer_length + 0.2
			var timer = get_tree().create_timer(timer_duration, true, false, true)
			
			# Add to a unique group to prevent conflicts and for easy cleanup.
			timer.add_to_group("higgs_finish_timer")
			
			# When timer finishes, call our cleanup function.
			timer.timeout.connect(_on_finish_timer_timeout)


# Called by the timer when we assume playback has finished.
func _on_finish_timer_timeout():
	# This is called after the audio generator's buffer should have played out.
	if _is_streaming: # Check if we weren't stopped manually in the meantime
		print("Finished playing audio stream.")
		_is_streaming = false # Set streaming to false to stop the _process loop.
		finished_playing_audio.emit()


# This helper function moves data from our pcm_buffer to the audio player.
func push_buffer_to_player():
	# This check is important, otherwise get_frames_available() could be called on a null object.
	if not is_instance_valid(audio_stream_generator_playback):
		return

	# How many audio frames can we push to the player right now?
	var frames_available = audio_stream_generator_playback.get_frames_available()
	if frames_available == 0:
		return

	# Each frame is mono 16-bit, which is 2 bytes.
	# How many bytes do we have in our buffer?
	var bytes_in_buffer = pcm_buffer.size()
	if bytes_in_buffer < 2:
		return

	# Determine how many frames we can actually create from our buffer.
	var frames_in_buffer = bytes_in_buffer / 2
	var frames_to_push = min(frames_available, frames_in_buffer)
	
	if frames_to_push > 0:
		var bytes_to_push = frames_to_push * 2
		
		# Process and push each frame.
		for i in range(frames_to_push):
			# Decode a 16-bit signed integer from the start of the buffer.
			var pcm_sample_s16 = pcm_buffer.decode_s16(i * 2)
			# Normalize it to a float between -1.0 and 1.0
			var pcm_sample_float = float(pcm_sample_s16) / 32767.0
			# Push the frame (Vector2 for stereo, but we use the same sample for both channels for mono).
			audio_stream_generator_playback.push_frame(Vector2(pcm_sample_float, pcm_sample_float))
			
		# Remove the data we just pushed from the buffer.
		pcm_buffer = pcm_buffer.slice(bytes_to_push)


# This function triggers the text-to-speech process.
func speak(text_to_speak: String, voice: String) -> void:
	print("Requesting speech stream for: '", text_to_speak, "'")
	
	# Stop any currently playing stream.
	stop_stream()

	# Reset state variables for the new stream.
	_is_streaming = true
	_connection_closed = false
	_http_error_found = false
	pcm_buffer.clear()
	
	# Connect to the server.
	# In Godot 4.2+, the third argument for connect_to_host is a TLSOptions object, not a boolean.
	var tls_options = TLSOptions.client() if USE_SSL else null
	var error = http_client.connect_to_host(HOST, PORT, tls_options)
	if error != OK:
		print_rich("[color=red]Failed to connect to host.[/color]")
		_is_streaming = false
		finished_playing_audio.emit() # Emit signal on failure
		return
		
	# Wait for the connection to be established.
	while http_client.get_status() == HTTPClient.STATUS_CONNECTING or http_client.get_status() == HTTPClient.STATUS_RESOLVING:
		http_client.poll()
		await get_tree().process_frame # Wait for one frame.

	if http_client.get_status() != HTTPClient.STATUS_CONNECTED:
		print_rich("[color=red]Connection failed with status: %d[/color]" % http_client.get_status())
		_is_streaming = false
		finished_playing_audio.emit() # Emit signal on failure
		return
		
	# Define the request body as a Dictionary.
	var body_dict = {
		"model": "higgs-audio-v2-generation-3B-base",
		"voice": voice,
		"input": text_to_speak,
		"response_format": "pcm"
	}
	var body_json_string = JSON.stringify(body_dict)
	
	# Define the necessary HTTP headers.
	var headers = [
		"Content-Type: application/json",
		"Host: %s" % HOST,
		"Connection: close"
	]
	
	# Send the POST request.
	error = http_client.request(HTTPClient.METHOD_POST, API_PATH, headers, body_json_string)
	if error != OK:
		print_rich("[color=red]An error occurred while sending the HTTP request.[/color]")
		_is_streaming = false
		finished_playing_audio.emit() # Emit signal on failure


# A function to manually stop the streaming and clean up.
func stop_stream():
	if _is_streaming:
		print("Stopping current stream.")
	http_client.close()
	_is_streaming = false
	_connection_closed = false
	pcm_buffer.clear()

	# Clean up any pending finish timer to prevent it from firing.
	for timer in get_tree().get_nodes_in_group("higgs_finish_timer"):
		timer.queue_free()

	# This clears any buffered audio that has not been played yet.
	if is_instance_valid(audio_stream_generator_playback):
		audio_stream_generator_playback.clear_buffer()
