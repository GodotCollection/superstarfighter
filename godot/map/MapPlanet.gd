tool
extends MapLocation

class_name MapPlanet

export (String, "invisible", "locked", "unlocked") var status setget set_status, get_status

export var set : Resource # Set
export var cursor_scene: PackedScene
onready var sprite = $Sprite
var cursors = [] # of Cursor

var not_available = false setget set_availability

signal updated
signal unlocked

func get_id() -> String:
	return set.get_id()

func get_status():
	return status
	
func set_status(v):
	status = v
	$Lock.visible = false
	if Engine.editor_hint:
		$Sprite.modulate = Color(1,1,1,1)
	elif status == TheUnlocker.UNLOCKED:
		$Sprite.modulate = Color(1,1,1,1)
	elif status == TheUnlocker.LOCKED:
		$Sprite.modulate = Color(0,0,0,0.5)
		$Lock.visible = true
	else:
		$Sprite.modulate = Color(0,0,0,0)
		
	$DebugLabel.text = status
	
func set_availability(value):
	not_available = value
	if sprite:
		$NA.visible = not_available
		
func set_set(v: Set):
	assert(v is Set)
	set = v
	
func get_set():
	return set
	
func act(cursor):
	.act(cursor)
	cursor.on_sth_pressed(status == TheUnlocker.UNLOCKED or status == TheUnlocker.LOCKED and cursor.is_winner())
	
func _ready():
	if set:
		sprite.texture = set.planet_sprite
		$Label.text = set.name
		
	self.set_status(TheUnlocker.get_status_set(self.get_id()))
	
func unlock():
	$AnimationPlayer.play("unlock")
	yield($AnimationPlayer, "animation_finished")
	emit_signal("unlocked")

func on_hover():
	$Label.visible = true
	
func on_blur():
	$Label.visible = false
	
func _on_tap(author: Ship):
	self.land_on(author)

	# remove author
	author.get_parent().remove_child(author)
	
func land_on(ship: Ship):
	var cursor: MapCursor = cursor_scene.instance()
	cursor.setup(ship.info_player)
	cursor.position = self.position
	get_parent().add_child(cursor)
	cursors.append(cursor)
	var i = 0
	for c in cursors:
		c.z_index = 100 - i
		c.set_rotation_degrees(60*(i - len(cursors)/2.0 + 0.5))
		c.wait = 0.25*i
		i+=1
