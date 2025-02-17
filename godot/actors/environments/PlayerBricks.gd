extends YSort

export var goal_owner : NodePath
var player

signal goal_done

var bricks := []

func _ready():
	for brick in get_children():
		if not brick is Brick:
			continue
			
		bricks.append(brick)
		brick.connect('killed', self, '_on_brick_destroyed')
		
	var player_spawner = get_node(goal_owner)
	if player_spawner:
		yield(player_spawner, "player_assigned")
		set_player(player_spawner.get_player())
		for brick in bricks:
			brick.set_color(player.species.color)
		
func get_score():
	return -1
	
func do_goal(player, pos):
	emit_signal("goal_done", player, self, pos)
	
func _on_brick_destroyed(brick, breaker):
	do_goal(get_player(), brick.global_position)

func set_player(v : InfoPlayer):
	player = v
	
func get_player():
	return player
