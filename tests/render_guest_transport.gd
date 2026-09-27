extends Node
## Screenshot-only transport stub so guest fixtures can claim local_id == 2 (#30).

var people: Array = []
var is_host = false
var room_code = "UP8-RENDER-GUEST"
var sent: Array = []


func session_open() -> bool:
	return true


func invite_ready() -> bool:
	return false


func send(message: Dictionary):
	sent.append(message.duplicate(true))


func send_to(_id: int, message: Dictionary):
	send(message)


func local_id() -> int:
	return 2


func participants() -> Array:
	return people
