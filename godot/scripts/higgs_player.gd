# TTS_Player.gd
# A simple Godot 4 Node that sends a text-to-speech request and plays the audio.
class_name HiggsPlayer
extends AudioStreamPlayer2D

# The HTTPRequest node is used to communicate with the web server.
var http_request = HTTPRequest.new()

# The URL for the text-to-speech API endpoint.
const TTS_API_URL = "http://45.67.213.138:20023/v1/audio/speech"
#const TTS_API_URL = "http://localhost:8000/v1/audio/speech"

signal finished_playing_audio()


# The _ready() function is called when the node enters the scene tree.
func _ready():
	# It's good practice to add nodes you create in code to the scene tree.
	add_child(http_request)
	
	# Connect the 'request_completed' signal from the HTTPRequest node
	# to our custom handler function. This function will be called when
	# the server responds.
	http_request.request_completed.connect(_on_request_completed)
	
	print("HiggsPlayer ready.")


# This function triggers the text-to-speech process.
# You can call this from anywhere to make the node speak.
func speak(text_to_speak: String, voice: String):
	print("Requesting speech for: '", text_to_speak, "'")
	
	# 1. Define the request body as a Dictionary.
	#    This matches the JSON data from the curl command.
	var body_dict = {
		"model": "higgs-audio-v2-generation-3B-base",
		"voice": voice,
		"input": text_to_speak,
		"response_format": "pcm"
	}
	
	# 2. Convert the Dictionary into a JSON string.
	var body_json_string = JSON.stringify(body_dict)
	
	# 3. Define the necessary HTTP headers.
	var headers = [
		"Content-Type: application/json"
	]
	
	# 4. Send the POST request.
	#    The request method is HTTPClient.METHOD_POST.
	#    The body of the request is our JSON string.
	var error = http_request.request(TTS_API_URL, headers, HTTPClient.METHOD_POST, body_json_string)
	
	# Check if the request was sent successfully.
	if error != OK:
		print_rich("[color=red]An error occurred while sending the HiggsPlayer HTTP request.[/color]")


# This function is the callback that handles the server's response.
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	# First, check if the request was successful (HTTP 200 OK).
	if response_code == 200:
		print("Speech audio received successfully.")
		
		# Create a new AudioStreamWAV resource. This type of stream is
		# perfect for handling raw audio data like PCM in Godot 4.
		var audio_stream = AudioStreamWAV.new()
		
		# The 'body' of the response is the raw audio data (PackedByteArray).
		audio_stream.data = body
		
		# Configure the stream to match the audio format from the server.
		# From the ffmpeg command: s16le -> 16-bit, ar 24000 -> 24000 Hz, ac 1 -> mono.
		audio_stream.format = AudioStreamWAV.FORMAT_16_BITS
		audio_stream.mix_rate = 24000
		audio_stream.stereo = false # false for mono, true for stereo
		
		# Assign our generated audio stream to the player.
		stream = audio_stream
		play()
		finished.connect(func(): finished_playing_audio.emit())
	else:
		# If the request failed, print the error code and message.
		var error_message = body.get_string_from_utf8()
		print_rich("[color=red]Request failed with code: %d[/color]" % response_code)
		print_rich("[color=red]Error message: %s[/color]" % error_message)
		finished_playing_audio.emit()
