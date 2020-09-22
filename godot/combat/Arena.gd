"""
Arena Node that will handle all the combat logic
"""
extends Node

class_name Arena

var width
var height
var someone_died = 0

export (PackedScene) var gameover_scene
export (bool) var demo = false
export (float) var size_multiplier = 2.0
export var time_scale : float = 1.0 setget set_time_scale, get_time_scale
export var game_mode : Resource # Gamemode - might be useful
export var planet_name : String

export var score_to_win_override : int = 0
export var match_duration_override : float = 0

var mockup: bool = false
var debug = false
# analytics
var run_time = 0

onready var crown_mode = $Managers/CrownModeManager
onready var kill_mode = $Managers/KillModeManager
onready var conquest_mode = $Managers/ConquestModeManager
onready var collect_mode = $Managers/CollectModeManager
onready var race_mode = $Managers/RaceModeManager
onready var goal_mode = $Managers/GoalModeManager
onready var survival_mode = $Managers/SurvivalModeManager

onready var combat_manager = $Managers/CombatManager
onready var stun_manager = $Managers/StunManager
onready var collect_manager = $Managers/CollectManager
onready var environments_manager = $Managers/EnvironmentsManager
onready var conquest_manager = $Managers/ConquestManager
onready var pursue_manager = $Managers/PursueManager
onready var snake_trail_manager = $Managers/TrailManager

onready var SpawnPlayers = $SpawnPositions/Players
onready var camera = $Camera
onready var canvas = $CanvasLayer
onready var hud = $CanvasLayer/HUD
onready var pause = $CanvasLayer/Pause
onready var mode_description = $CanvasLayer/DescriptionMode
onready var grid = $Battlefield/Background/Grid
onready var deathflash_scene = preload('res://actors/battlers/DeathFlash.tscn')

signal screensize_changed(screensize)
signal gameover
signal restart
signal rematch
signal back_to_menu
signal slomo
signal unslomo
signal battle_start

var array_players = [] # Dictionary of InfoPlayers

var scores : MatchScores

var session: SessionScores
func initialize(_session) -> void:
	session = _session
	
func compute_arena_size():
	"""
	compute the battlefield size
	"""
	return $Battlefield/Background/OutsideWall.get_rect_extents()

func set_time_scale(value):
	time_scale = value
	update_time_scale()
	
func get_time_scale():
	return time_scale
	
func update_time_scale():
	Engine.time_scale = time_scale

signal update_stats

func setup_level(mode : Resource):
	assert(mode is GameMode)
	# mode managers
	crown_mode.enabled = mode.crown
	kill_mode.enabled = mode.death
	collect_mode.enabled = mode.collect
	conquest_mode.enabled = mode.hive
	goal_mode.enabled = mode.goal
	survival_mode.enabled = mode.survival
	race_mode.enabled = mode.race
	
	# managers
	pursue_manager.enabled = mode.pursuing_bombs
	
	#FIX
	if session and mode.name in session.settings and not global.campaign_mode:
		for key in session.settings[mode.name]:
			var val = session.settings[mode.name][key]
			mode.set(key, val)
			# send stats for settings
			global.send_stats("design", {"event_id": "settings:{what}:{sport}".format({"what": key, "sport": mode.name}), "value": int(val)})
	
func _ready():
	set_process(false)
	# Pick controller label
	$CanvasLayer/DemoLabel.visible = demo
	
	
	# Setup goal, Gear and mode managers
	setup_level(game_mode)

	compute_arena_size()
	camera.zoom *= size_multiplier
	
	# Engine.time_scale = 0.2
	# in order to get the size
	get_tree().get_root().connect("size_changed", self, "compute_arena_size")
	run_time = OS.get_ticks_msec()
	
	# get number of players
	# n_players = get_num_players()
	
	# Analytics
	analytics.start_elapsed_time()
	

	scores = MatchScores.new()
	scores.connect("game_over", self, "on_gamemode_gameover")
	connect("update_stats", scores, "update_stats")
	connect("slomo", environments_manager, "activate_slomo", [self], CONNECT_ONESHOT)
	
	
	collect_manager.connect('collected', crown_mode, "_on_sth_collected")
	collect_manager.connect('collected', self, "_on_sth_collected")
	collect_manager.connect('dropped', crown_mode, "_on_sth_dropped")
	collect_manager.connect('dropped', self, "_on_sth_dropped")
	collect_manager.connect("stolen", crown_mode, "_on_sth_stolen")
	environments_manager.connect('repel_cargo', collect_manager, "_on_cargo_repelled")
	collect_manager.connect('collected', collect_mode, "_on_sth_collected")
	collect_manager.connect('coins_dropped', collect_mode, "_on_coins_dropped")
	collect_manager.connect('coins_dropped', self, "_on_coins_dropped")
	conquest_manager.connect('conquered', conquest_mode, "_on_sth_conquered")
	conquest_manager.connect('lost', conquest_mode, "_on_sth_lost")
	
	crown_mode.connect('score', scores, "add_score")
	kill_mode.connect('score', scores, "add_score")
	kill_mode.connect('broadcast_score', scores, "broadcast_score")
	kill_mode.connect('show_score', self, "spawn_points_scored")
	race_mode.connect('score', scores, "add_score")
	race_mode.connect('show_score', self, "spawn_points_scored")
	conquest_mode.connect('score', scores, "add_score")
	collect_mode.connect('score', scores, "add_score")
	collect_mode.connect('show_score', self, "spawn_points_scored")
	collect_mode.connect('spawn_next', self, "on_next_wave")
	goal_mode.connect('score', scores, "add_score")
	goal_mode.connect('show_score', self, "spawn_points_scored")
	survival_mode.connect('score', scores, "add_score")
	
	for portal in get_tree().get_nodes_in_group("goal"):
		portal.connect('went_through', race_mode, "_on_lap_done")
		portal.connect('goal_done', goal_mode, "_on_goal_done")
		
	var standalone : bool = true
	var players = {}
	var array_players = []
	
	if session:
		array_players = session.players.values()
		standalone = false
	else:
		session = SessionScores.new()
	
	var spawners = $SpawnPositions/Players.get_children()
	# Randomize player position at start: https://github.com/notapixelstudio/superstarfighter/issues/399
	# works with a session, not if you run from scene
	spawners.shuffle()
	# set up the spawners
	var i = 0
	for s in spawners:
		var key = s.name
		var info_player = InfoPlayer.new()
		if standalone or s.species.species_name == 'drones':
			
			info_player.cpu = s.cpu
			info_player.species = s.species
			info_player.controls = s.controls
			if s.species.species_name == 'drones':
				info_player.id = 'drones'
			elif s.cpu:
				info_player.id = "cpu"+str(i+1)
			else:
				info_player.id = s.name
			
		else:
			info_player = array_players[i] 
			s.info_player = info_player
			s.controls = info_player.controls
			s.species = info_player.species
			s.cpu = info_player.cpu
		
		s.info_player = info_player
		players[info_player.id] = info_player
	
		i += 1
	
	session.players = players
		
	if conquest_mode.enabled:
		score_to_win_override = floor(len(get_tree().get_nodes_in_group('cell'))/2)+1
	
	scores.initialize(players, game_mode, score_to_win_override, match_duration_override)

	session.add_match(scores)
	# initialize HUD
	hud.initialize(session)
	
	camera.initialize(compute_arena_size())
	$Battlefield.visible = false
	if score_to_win_override > 0:
		game_mode.max_score = score_to_win_override
	if match_duration_override > 0:
		game_mode.max_timeout = match_duration_override
	mode_description.gamemode = game_mode
	mode_description.appears()
	if demo:
		# demo will wait 1 second and create a CPU match
		mode_description.demomode(demo)
		mode_description.set_process_input(false)
		yield(get_tree().create_timer(3), "timeout")
		mode_description.disappears()
	camera.isShake = true
	yield(mode_description, "ready_to_fight")
	$Battlefield.visible = true
	hud.set_planet("", game_mode)
	
	update_grid()
	
	# FIXME
	for well in get_tree().get_nodes_in_group('gravity_wells_on'):
		well.enabled = true
	
	# set up hive cells
	
	#for cell in get_tree().get_nodes_in_group('cell'):
	#	var skip = false
	#	for player_spawner in $SpawnPositions/Players.get_children():
	#		if (cell.position - player_spawner.position).length() < 600:
	#			skip = true
	#			break
	#	
	#	if skip:
	#		continue
	#	
	#	if pow(randf(),2) > 0.95:
	#		var wall = wall_scene.instance()
	#		var gshape = cell.get_gshape()
	#		cell.remove_child(gshape)
	#		wall.add_child(gshape)
	#		wall.position = cell.position
	#		wall.rotation = cell.rotation
	#		#wall.fill_color = Color(0.8,0.8,0.8,1)
	#		#wall.modulate = Color(0.5,0.5,0.5,1)
	#		wall.scale = Vector2(0.8,0.8)
	#		$Battlefield.add_child(wall)
	#		cell.queue_free()
	var ships = []
	
	# environment spawner: coins, etc.
	if get_tree().get_nodes_in_group("spawner_group"):
		focus_in_camera.activate()
		collect_mode.initialize(get_tree().get_nodes_in_group("spawner_group"))
		
	# connect already placed killable stuff (bricks, aliens, etc.)
	for sth in get_tree().get_nodes_in_group("killables"):
		sth.connect('killed', kill_mode, '_on_sth_killed')
		
	# manage level flooding
	if (session.get_mutator('flood') and game_mode.floodable and randf() < 0.33) or game_mode.flood:
		var level_height = compute_arena_size().size.y
		var water_rect_height = $Battlefield/Background/FloodWater/GRect.height
		$Battlefield/Background/FloodWater.position.y = water_rect_height/2 + level_height/2
		var flood_animation =  $Battlefield/Background/FloodWater/AnimationPlayer.get_animation('Rotate')
		flood_animation.track_set_key_value(0, 0, Vector2(0, water_rect_height/2 + level_height/2))
		flood_animation.track_set_key_value(0, 1, Vector2(0, water_rect_height/2 - level_height/2))
		flood_animation.track_set_key_time(0, 1, game_mode.max_timeout) # filled as the countdown is done
	else:
		$Battlefield/Background/FloodWater.queue_free()
		
	# manage level lasering
	if (session.get_mutator('laser') and game_mode.laserable and randf() < 0.33) or game_mode.additional_lasers:
		for laser_anim in get_tree().get_nodes_in_group('animation_if_additional_lasers'):
			laser_anim.play('Default')
	else:
		for laser in get_tree().get_nodes_in_group('additional_lasers'):
			laser.queue_free()
		
	if not mockup:
		Soundtrack.play("Fight", true)
	else:
		hud.visible = false
	if not mockup:
		
		var j = 0
		var player_spawners = $SpawnPositions/Players.get_children()
		get_tree().paused = true
		for s in player_spawners:
			var spawner = s as PlayerSpawner
			spawner.appears()
			# waiting for the ship to be entered
			yield(get_tree().create_timer(0.5), "timeout")
			ships.append(spawn_ship(spawner))
			j += 1
			# wait for the last ship
			if j >= len(player_spawners):
				yield(spawner, "entered_battlefield")
				
		get_tree().paused = false
		camera.activate_camera()

	else:
		spawn_ships()
	
	yield(get_tree().create_timer(0.1), "timeout") # FIXME workaround to wait for all ships

	for bomb_spawner in get_tree().get_nodes_in_group("spawner"):
		bomb_spawner.initialize(self)
		if bomb_spawner.owned_by_player and $Battlefield/Foreground.has_node(bomb_spawner.owned_by_player):
			bomb_spawner.owner_ship = $Battlefield/Foreground.get_node(bomb_spawner.owned_by_player)

		bomb_spawner.spawn()
	for turret in get_tree().get_nodes_in_group("turret"):
		turret.initialize(self)
		
	update_time_scale()
	set_process(true)
	for anim in get_tree().get_nodes_in_group("animation_in_battle"):
		anim.play("Rotate")
		
	emit_signal('battle_start')
	
	for node in get_tree().get_nodes_in_group('wait_to_start'):
		node.start()
	
func focus_in_camera(node: Node2D, wait_time: float):
	focus_in_camera.move(node.position, wait_time)
	
const COUNTDOWN_LIMIT = 5.0

func update_grid():
	grid.polygon = $Battlefield/Background/OutsideWall.get_gshape().to_PoolVector2Array()
	
func _process(delta):
	scores.update(delta)
	update_grid()
	
	slomo()
	
	if int(scores.time_left) == COUNTDOWN_LIMIT -1 and not $CanvasLayer/Countdown/AudioStreamPlayer.playing:
		$CanvasLayer/Countdown/AudioStreamPlayer.play()
	if scores.time_left < COUNTDOWN_LIMIT and scores.time_left > 0:
		$CanvasLayer/Countdown.text = str(int(ceil(scores.time_left)))
	else:
		$CanvasLayer/Countdown.text = ""

func _input(event):
	if demo:
		if event is InputEventKey or event is InputEventJoypadButton:
			emit_signal("back_to_menu")
			
func _unhandled_input(event):
	if event.is_action_pressed("pause") and not global.demo and not scores.game_over:
		pause.start()
		
	var debug_pressed = event.is_action_pressed("debug")
	if debug_pressed:
		debug = not debug
		OS.window_fullscreen = !OS.window_fullscreen
		# DebugNode.visible = debug
		
	# reset by command only through debug
	if event.is_action_pressed('continue') and debug:
		reset(global.level)
	
func reset(level):
	someone_died = false
	get_tree().change_scene_to(load("res://screens/game_screen/levels/"+level))

func get_num_players()->int:
	"""
	Depending on the arena we are in.
	Works after ready
	"""
	return SpawnPlayers.get_child_count()

func _on_background_item_rect_changed():
	print_debug("Windows changed")

func hud_update(player_id : String, score:int, collectable_owner:String = ""):
	hud._on_Arena_update_score(player_id, score, collectable_owner)

func ship_just_died(ship, killer):
	"""
	Parameters
	----------
		ship : Ship
		killer: Ship
		
	"""
	# stats
	# TODO: maybe somewhere else
	emit_signal("update_stats", ship.info_player, 1, "deaths")
	if killer and killer is Ship and killer != ship:
		emit_signal("update_stats", killer.info_player, 1, "kills")
	else:
		emit_signal("update_stats", ship.info_player, 1, "selfkills")
	
	$Battlefield.call_deferred("remove_child", ship)
	
	var deathflash = deathflash_scene.instance()
	deathflash.species = ship.species
	deathflash.position = ship.position
	$Battlefield.call_deferred("add_child", deathflash)
	$Battlefield.call_deferred("add_child", ship.dead_ship_instance)
	
	ship.dead_ship_instance.apply_central_impulse(-ship.linear_velocity)
	ship.dead_ship_instance.apply_torque_impulse(ship.linear_velocity.length()*20)
	
	if ship.info_player.lives == 0:
		var alive_players = []
		var focus = load("res://actors/environments/ElementInCamera.tscn").instance()
		ship.dead_ship_instance.remove_from_group("in_camera")
		$Battlefield.add_child(focus)
		yield(get_tree(), "idle_frame")
		
		for s in get_tree().get_nodes_in_group('players'):
			if s.alive:
				alive_players.append(s)
		
		focus.manual_activate($CenterCamera, ship.dead_ship_instance.position, len(alive_players))
		if len(alive_players) == 1:
			# notify scores if there is only one player left
			yield(get_tree().create_timer(1), 'timeout')
			scores.one_player_left(alive_players[0].info_player)
			
		elif len(alive_players) == 0:
			# notify scores if there are no players left
			yield(get_tree().create_timer(0.3), 'timeout')
			scores.no_players_left()
		
		# skip respawn if there are no lives left
		return
	
	var respawn_timeout = 1.5
	if crown_mode.enabled:
		if len(ECM.entities_with('Royal')) > 0:
			if ECM.E(ship).has('Royal'):
				respawn_timeout = 2.25
			else:
				respawn_timeout = 0.75
	elif conquest_mode.enabled:
		respawn_timeout = 0.75
	
	yield(get_tree().create_timer(respawn_timeout), "timeout")
	
	if scores.game_over:
		return
	
	# respawn
	
	ship.linear_velocity = ship.dead_ship_instance.linear_velocity
	ship.angular_velocity = ship.dead_ship_instance.angular_velocity
	$Battlefield.call_deferred("remove_child", ship.dead_ship_instance)
	ship.position = ship.dead_ship_instance.position
	ship.rotation = ship.dead_ship_instance.rotation
	$Battlefield.call_deferred("add_child", ship)
	create_trail(ship)
	
	
func on_gamemode_gameover(winners: Array):
	if demo:
		emit_signal("back_to_menu")
		return
	for child in $Managers.get_children():
		if child is ModeManager:
			child.enabled = false
	camera.stop_and_zoomout(compute_arena_size())
	$GameOverAnim.play('Game Over')
	yield($GameOverAnim, "animation_finished") # wait for animation and UI redraw (esp. bars)
	set_time_scale(1)
	get_tree().paused = true
	var game_over = gameover_scene.instance()
	game_over.connect("rematch", self, "_on_GameOver_rematch")
	game_over.connect("back_to_menu", self, "_on_Pause_back_to_menu")
	canvas.add_child(game_over)
	
	game_over.initialize(winners, scores)


const ship_scene = preload("res://actors/battlers/Ship.tscn")
const cpu_ship_scene = preload("res://actors/battlers/CPUShip.tscn")
const trail_scene = preload("res://actors/battlers/TrailNode.tscn")

onready var focus_in_camera = $Battlefield/Overlay/ElementInCamera

func spawn_ships():
	for player in SpawnPlayers.get_children():
		spawn_ship(player)

func create_trail(ship):
	# create and link trail
	var trail = trail_scene.instance()
	$Battlefield.add_child(trail)
	yield(trail, "ready")
	trail.initialize(ship)
	trail.configure(game_mode.deadly_trails, game_mode.deadly_trails_duration)
	return trail

func spawn_ship(player:PlayerSpawner):
	var ship
	if player.is_cpu():
		ship = cpu_ship_scene.instance()
	else:
		ship = ship_scene.instance()
	
	ship.scores = scores
	ship.camera = camera
	ship.controls = player.controls
	ship.species = player.species
	ship.position = player.position
	ship.rotation = player.rotation
	ship.height = height
	ship.width = width
	ship.name = player.name
	ship.info_player = player.info_player
	yield(player, "entered_battlefield")
	
	$Battlefield.add_child(ship)
	
	# create and link trail
	var trail = trail_scene.instance()
	$Battlefield.add_child(trail)
	yield(trail, "ready")
	trail.initialize(ship)
	trail.configure(game_mode.deadly_trails, game_mode.deadly_trails_duration)
	
	# Check on gears
	ship.set_bombs_enabled(game_mode.shoot_bombs)
	ship.set_bomb_type(game_mode.bomb_type)
	ship.set_ammo(game_mode.starting_ammo)
	ship.set_reload_time(game_mode.reload_time)
	ship.set_lives(game_mode.starting_lives)
	
	
	# connect signals
	ship.connect("dead", self, "ship_just_died")
	ship.connect("spawn_bomb", self, "spawn_bomb", [ship])
	ship.connect("near_area_entered", combat_manager, "_on_ship_collided")
	ship.connect("body_entered", combat_manager, "_on_ship_collided", [ship])
	ship.connect("near_area_entered", collect_manager, "ship_near_area_entered")
	ship.connect("body_entered", environments_manager, "_on_sth_entered", [ship])
	ship.connect("near_area_entered", environments_manager, "_on_sth_entered")
	ship.connect("near_area_exited", environments_manager, "_on_sth_exited")
	ship.connect("detection", pursue_manager, "_on_ship_detected")
	ship.connect("body_entered", stun_manager, "ship_collided", [ship])
	ship.connect("dead", kill_mode, "_on_sth_killed")
	ship.connect("dead", collect_manager, "_on_ship_killed")
	ship.connect("near_area_entered", conquest_manager, "_on_ship_collided")
	ship.connect("near_area_entered", snake_trail_manager, "_on_ship_collided")
	
	
	# attach followcamera
	var follow = load("res://actors/battlers/FollowCamera.tscn").instance()
	follow.node_owner = ship.get_node("TargetDest")
	follow.add_to_group("in_camera")
	$Battlefield.add_child(follow)
	ship.connect("dead", follow, "ship_just_died")
	
	
	crown_mode.connect('show_score', ship, "update_score")
	return ship
	
const bomb_scene = preload('res://actors/weapons/Bomb.tscn')
func spawn_bomb(type, pos, impulse, ship, size=1):
	var bomb = bomb_scene.instance()
	bomb.initialize(type, pos, impulse, ship, size)
	
	bomb.connect("near_area_entered", combat_manager, "bomb_near_area_entered")
	bomb.connect("near_area_entered", environments_manager, "_on_sth_entered")
	bomb.connect("near_area_exited", environments_manager, "_on_sth_exited")
	bomb.connect("detonate", self, "bomb_detonated", [bomb])
	
	$Battlefield.add_child(bomb)
	
	if ship:
		emit_signal("update_stats", ship.info_player, 1, "bombs")
	
	return bomb

func bomb_detonated(bomb):
	grid.add_well(bomb)
	
const points_scored_scene = preload('res://special_scenes/on_canvas_ui/PointsScored.tscn')

func spawn_points_scored(species: Species, score, pos):
	var points_scored = points_scored_scene.instance()
	points_scored.set_points(score)
	points_scored.scale = camera.zoom
	points_scored.position = pos
	points_scored.modulate = species.color
	$Battlefield.add_child(points_scored)

func _on_sth_collected(collector, collectee):
	if collectee.get_parent().is_in_group("spawner_group"):
		collectee.get_parent().call_deferred('remove', collectee)
	else:
		$Battlefield.call_deferred('remove_child', collectee) # collisions do not work as expected without defer
		
func _on_sth_dropped(dropper, droppee):
	$Battlefield.add_child(droppee)
	droppee.position = dropper.position
	droppee.linear_velocity = dropper.linear_velocity
	
	# wait a bit, then make the item collectable again
	yield(get_tree().create_timer(0.2), "timeout")
	ECM.E(droppee).get('Collectable').enable()
	# retrigger bodies already entered
	yield(get_tree().create_timer(0.5), "timeout")
	dropper.recheck_colliding()
	
#func _on_coins_dropped(dropper, amount):
#	for i in range(amount):
#		var coin = coin_scene.instance()
#		$Battlefield.add_child(coin)
#		coin.position = dropper.position
#		coin.linear_velocity = dropper.linear_velocity + Vector2(500,0).rotated(randi()/8/PI)

func on_next_wave(diamonds, wait_time=1):
	if wait_time:
		focus_in_camera.move(diamonds.position, wait_time)
		yield(focus_in_camera, "completed") 
	diamonds.spawn()
	collect_mode.on_wave_ready()
	
	#for collectable in collectables:
	#	$Battlefield.add_child(collectable)
		
func _on_Pause_back_to_menu():
	emit_signal("back_to_menu")

func _on_GameOver_rematch():
	emit_signal("rematch")

func _on_Pause_restart():
	emit_signal("restart")

func _on_Pause_skip():
	emit_signal("rematch") # WARNING this should be different if we are keeping scores
	
const max_slomo_elements = 7

func slomo():
	
	if len(get_tree().get_nodes_in_group('slomo')) > max_slomo_elements:
		emit_signal("slomo")
		self.time_scale = lerp(time_scale, 0.5, 0.2)
	else:
		emit_signal("unslomo")
		self.time_scale = lerp(time_scale, 1, 0.1)
		
func _on_Rock_request_spawn(child):
	if child is Rock:
		child.connect('request_spawn', self, '_on_Rock_request_spawn')
	$Battlefield.add_child(child)
	
