class_name LlmApi
extends Node

# Constants
# const LLM_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
const LLM_API_URL = "http://localhost:3000/llm"
const LLM_API_KEY = "<YOUR API KEY HERE>"

# Child nodes
@onready var http_request: HTTPRequest = $HTTPRequest

# Signals
signal character_response_received(response_text: String)

# Class variables (configuration)
@export var character_name: String = "peter"

# State variables
var activity_history: Array[String] = []

func read_sys_prompt() -> String:
	return """
# Murder Mystery Adventure Game: Murder on the Higgs Express

## Overview

- This is a single player story-driven adventure game called "Murder on the Higgs Express", inspired by the book "Murder on the Orient Express".
- The player's objective is to solve the murder mystery.

## Win Condition

- The player is an undercover detective.
- As soon as the player makes a final accusation, the game ends.
- The player wins if they guess the murderer correctly, and lose if not.
- If the player guesses wrongly, the real murderer is never revealed.
- This is to create suspense. The real murderer goes free due to the player's failures.

## Character Dossiers

- Murdock: The player's character. His cover job is a software developer. His true job is an undercover detective. On vacation, Murdock is taking the train back to Toronto from a well deserved vacation in Ottawa.
- Luthen: (A character inspired by Star Wars: Andor)
- Walter: (A character inspired by Breaking Bad)
- Buster: (A character inspired by The Ballad of Buster Scruggs)
- Morgan: (A character inspired by Morgan Freeman the Actor)
- Peter: (A character inspired by Family Guy)
- Emmanuel: (An african pastor)

---

### 1. Murder Culprit

* **Walter**

### 2. Motive, Weapon, and Method

* **Victim:** Dr. Aris Thorne, a Nobel-laureate physicist.
* **Motive:** Revenge. Years ago, Dr. Thorne stole Walter’s groundbreaking research on molecular synthesis, published it as his own, and ruined Walter's academic career. Walter has been meticulously plotting his revenge ever since.
* **Weapon:** A custom-synthesized, fast-acting neurotoxin delivered via a spring-loaded needle hidden inside a fountain pen. The toxin induces symptoms that closely mimic a massive, fatal stroke.
* **Method:** Walter requested a private meeting with Dr. Thorne in the victim's compartment under the guise of being an admirer of his work. During the meeting, while handing Thorne a document to "autograph," Walter discreetly pricked him in the hand with the poisoned pen. The toxin worked within a minute, and Walter left the compartment before the body was discovered.

### 3. Murder Location and Time

* **Location:** Inside Dr. Thorne’s private sleeper car.
* **Time:** Approximately 10:45 PM, after most passengers had retired for the evening.

### 4. Character Dossiers

* **Luthen:** An impeccably dressed and calculating antiquities dealer. He is reserved, observant, and speaks with unnerving precision. He was attempting to acquire sensitive, and potentially dangerous, data from Dr. Thorne, who refused the sale. Luthen is motivated by profit and the acquisition of rare, powerful knowledge.

* **Walter (The Murderer):** A seemingly frail and unassuming retired chemistry teacher. He is meticulous, soft-spoken, and constantly cleaning his glasses. He carries an air of quiet resignation, but beneath it lies a cold, calculating rage born from a lifetime of intellectual theft and public humiliation at the hands of Dr. Thorne.

* **Buster:** A cheerful, silver-tongued traveling musician with a guitar that never leaves his side. He is a known gambler and raconteur. Dr. Thorne had recently bailed Buster out of a significant debt, and Buster was seen arguing heatedly with him earlier in the day, possibly over repayment terms.

* **Morgan:** A world-renowned documentary narrator with a famously calm and authoritative voice. He was on board to interview Dr. Thorne for a new film. He is professional and patient, but discovered during his research that Thorne's latest project had catastrophic military applications, a fact that deeply troubled his pacifist principles.

* **Peter:** A loud, obnoxious, and heavyset man who works as a regional sales manager for a brewery. He is prone to inappropriate humor and heavy drinking. He took a strong, public dislike to Dr. Thorne's condescending attitude at dinner and was overheard making a drunken threat against him.

* **Emmanuel:** A charismatic Nigerian pastor traveling to a religious conference in Toronto. He is serene, speaks in parables, and carries an aura of profound faith. He found Dr. Thorne's outspoken and militant atheism to be a deep spiritual offense and believed the man was a corrupting influence on the world.
"""

	## For user data, you would use a path like "user://save_data.txt"
	#var sys_prompt_path = "res://assets/prompts/sys_prompt.md"
#
	## 1. Check if the file exists first.
	#if not FileAccess.file_exists(sys_prompt_path):
		#print("Error: System prompt file not found at path: ", sys_prompt_path)
		#return "" # Exit the function if the file doesn't exist.
#
	## 2. Try to open the file.
	#var file = FileAccess.open(sys_prompt_path, FileAccess.READ)
#
	## 3. Check if opening was successful.
	#if file:
		#var content = file.get_as_text()
		##print("Successfully read file content: \n", content)
		#return content
	#
	## This will catch other errors, like permission issues.
	#var error = FileAccess.get_open_error()
	#print("File open error: ", error)	
	#return ""

func talk_to_char(message: String):
	activity_history.append("[murdock] " + message)

	var body_dict = {
		"contents": [
			{
				"parts": [
					{
						"text": read_sys_prompt() + """
---

Standing in front of: """ + character_name + """

Activity History:
""" + "\n".join(activity_history) + """
Instruction:
	
- Provide the next narrator line.
- If the player makes an accusation, the game is over.
- If the player provides a dialogue line instead of an action, assume they are talking to """ + character_name
					}
				]
			}
		],
		"generationConfig": {
			"thinkingConfig": {
				"thinkingBudget": 0 # disable reasoning for speed
			},
			"responseMimeType": "application/json",
			"responseSchema": {
				"type": "OBJECT",
				"properties": {
					"is_game_over_good_ending": {"type": "BOOLEAN"},
					"is_game_over_bad_ending": {"type": "BOOLEAN"},
					"narrator_line": {"type": "STRING"}
				}
			}
		}
	}
	var body_json_string = JSON.stringify(body_dict)
	
	var headers = [
		"Content-Type: application/json",
		#"x-goog-api-key: " + LLM_API_KEY
	]
	
	if http_request.request(LLM_API_URL, headers, HTTPClient.METHOD_POST, body_json_string) != OK:
		print_rich("[color=red]An error occurred while sending the LlmApi HTTP request.[/color]")
	
	print("LLM API: Request sent.")
	

func _ready() -> void:
	http_request.request_completed.connect(_on_request_completed)


func _on_request_completed(result, response_code, headers, body):
	var response = JSON.parse_string(body.get_string_from_utf8())
	var payload = JSON.parse_string(response["candidates"][0]["content"]["parts"][0]["text"])
	
	activity_history.append("[narrator] {%s}" % payload.narrator_line)

	if payload.is_game_over_good_ending:
		GameState.is_game_over_good_ending = true
	elif payload.is_game_over_bad_ending:
		GameState.is_game_over_bad_ending = true
	
	character_response_received.emit(payload.narrator_line)
