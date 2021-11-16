tool
extends RigidBody2D

class_name Ball

const GRAB_DISTANCE = 84

export (String, 'crown', 'bee_crown', 'basket', 'soccer', 'tennis', 'heart', 'star', 'negacrown', 'skull') var type setget set_type, get_type

var impulse := 0.0
var trail

func set_type(v):
	type = v
	refresh()
	
func get_type():
	return type
	
func _ready():
	if type == 'soccer':
		impulse = 5
	set_physics_process(false)
	refresh()
	
func _enter_tree():
	trail = Trail2D.new()
	trail.gradient = Gradient.new()
	trail.gradient.set_color(0, Color(1,1,1,0))
	trail.gradient.set_color(1, Color(1,1,1,0.1))
	trail.trail_length = 30
	trail.width = 90
	add_child(trail)
	
func _exit_tree():
	remove_child(trail)
	get_parent().add_child(trail)
	trail.disappear()
	
func refresh():
	if not is_inside_tree():
		yield(self, 'ready')
	$Sprite.texture = load('res://assets/sprites/balls/'+type+'.png')
	
func place_and_push(dropper, velocity, direction:='forward') -> void:
	var dir = 1.0 if direction == 'forward' else -1.0
	global_position = dropper.global_position
	global_position = dropper.global_position + dir*Vector2(GRAB_DISTANCE,0).rotated(dropper.global_rotation)
	
	linear_velocity = velocity if direction == 'forward' else -300.0*velocity.normalized()
	if type == 'soccer':
		linear_velocity *= 1.5
		
	activate()

func activate():
	set_physics_process(impulse > 0)
	
func _physics_process(_delta):
	apply_central_impulse(impulse*Vector2(1,0).rotated(linear_velocity.angle()))
	
func get_strategy(ship, distance, game_mode):
	return {"seek": 10}
	
func get_texture():
	return $Sprite.texture
	
func show_on_top():
	return type in ['crown', 'negacrown', 'bee_crown']
	
func is_rotatable():
	return not type in ['crown', 'negacrown', 'bee_crown', 'star', 'skull']

func is_loadable():
	return is_inside_tree()
	
func has_type(t):
	return self.get_type() == t
	
func is_equivalent_to(holdable2):
	return self.has_type(holdable2.get_type())
	
