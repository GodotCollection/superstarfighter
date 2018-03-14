extends KinematicBody2D

var left
var right
export var velocity = Vector2(6,0)
var speed_multiplier = 1

const ROTATION_SPEED = 0.1

const RADIUS = 16

var width
var height

export var color = Color(0,0,0)
export var player = 'p1'

func _ready():
	$Circle.color = color
	$Circle.radius = RADIUS
	width = get_viewport().size.x
	height = get_viewport().size.y
	print(width)

func _physics_process(delta):
	left = Input.is_action_pressed(player+'_left')
	right = Input.is_action_pressed(player+'_right')
	
	if left and not right:
		steer(-ROTATION_SPEED)
	elif right and not left:
		steer(ROTATION_SPEED)
		
	# dash
	if Input.is_action_just_pressed(player+'_act'):
		speed_multiplier = 3
		
	move_and_collide(velocity * speed_multiplier)
	
	# wrap
	if position.x > width:
		position.x -= width
	elif position.x <= width:
		position.x += width
		
	if position.y > height:
		position.y -= height
	elif position.y <= height:
		position.y += height
	
	# dash recover
	speed_multiplier = max(1, speed_multiplier - 0.1)
	
# Steer the ship _rad_ radians clockwise.
func steer(rad):
	velocity = velocity.rotated(rad)
	rotate(rad)