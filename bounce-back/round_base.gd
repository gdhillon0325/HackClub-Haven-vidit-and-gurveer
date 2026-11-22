extends Node2D

# round_base.gd - all the game logic for ONE round scene.
# Each round (round1.tscn, round2.tscn, round3.tscn) has its own tiny script
# (round1.gd, ...) that extends this file and sets its own numbers.
# Every round scene runs on its own: open it and press F6 (Run Current Scene).

@export var round_number: int = 1
@export var total_rounds: int = 3
@export var echoes_for_round: int = 5
@export_file("*.tscn") var next_scene: String = ""        # empty = last round
@export_file("*.tscn") var first_scene: String = "res://round1.tscn"

@export var player_speed: float = 260.0
@export var jump_velocity: float = -430.0
@export var gravity_force: float = 980.0
@export var sonar_ray_count: int = 48
@export var sonar_speed: float = 640.0
@export var sonar_bounces: int = 2
@export var sonar_curve: float = 1.4        # how much sonar lines bend (radians/sec). 0 = straight
@export var spike_rest_alpha: float = 0.15  # how visible spikes stay in the dark. 0 = fully hidden
@export var void_death_y: float = 820.0
@export var floor_spikes: bool = true
@export var floor_spike_y: float = 632.0

var player: CharacterBody2D
var player_sprite: Sprite2D
var echoes_left: int = 0
var echo_cooldown: float = 0.0
var game_won: bool = false
var r_was_down: bool = false
var changing_scene: bool = false

var revealed_sprites: Dictionary = {}
var sonar_rays: Array = []
var echo_rings: Array = []
var corpse_platforms: Array = []
var hud_label: Label
var overlay: Node2D


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	_ensure_environment()
	_create_hud()
	overlay = Node2D.new()
	overlay.z_index = 10
	overlay.draw.connect(_on_overlay_draw)
	add_child(overlay)
	_create_cave_background()
	_create_player()
	_setup_round_objects()
	echoes_left = echoes_for_round
	_update_hud()


func _ensure_environment() -> void:
	for child in get_children():
		if child is WorldEnvironment:
			return
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_bloom = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _create_player() -> void:
	if has_node("Player"):
		player = $Player
		player_sprite = $Player/Sprite2D
	else:
		player = CharacterBody2D.new()
		player.name = "Player"
		player.collision_layer = 1
		player.collision_mask = 2
		var col := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(28, 28)
		col.shape = rect
		player.add_child(col)
		player_sprite = Sprite2D.new()
		player_sprite.name = "Sprite2D"
		player.add_child(player_sprite)
		add_child(player)
	if player_sprite.texture == null:
		player_sprite.texture = _make_shrew_texture()


func _setup_round_objects() -> void:
	var platforms = get_node_or_null("Platforms")
	if platforms:
		for plat in platforms.get_children():
			plat.add_to_group("echo_surface")
			var spr: Sprite2D = plat.get_node_or_null("Sprite2D")
			if spr and spr.texture == null:
				spr.texture = _make_rock_texture(Vector2i(120, 24), str(plat.name).hash())
			if spr:
				spr.modulate = Color(0.15, 0.95, 1.0, 0.0)

	var hazards = get_node_or_null("Hazards")
	if hazards == null:
		hazards = Node2D.new()
		hazards.name = "Hazards"
		add_child(hazards)
	if floor_spikes:
		_build_floor_spikes(hazards)
	for haz in hazards.get_children():
		haz.add_to_group("hazard")
		var spr: Sprite2D = haz.get_node_or_null("Sprite2D")
		if spr and spr.texture == null:
			spr.texture = _make_spike_texture()
		if spr:
			spr.modulate = Color(0.8, 0.82, 0.86, spike_rest_alpha)  # gray spikes

	var door: Area2D = get_node_or_null("ExitDoor")
	if door:
		door.body_entered.connect(_on_exit_door_entered)
		var door_spr: Sprite2D = door.get_node_or_null("Sprite2D")
		if door_spr:
			if door_spr.texture == null:
				door_spr.texture = _make_door_texture()
			door_spr.modulate = Color(0.2, 1.0, 0.45, 1.0)

	_respawn_player()


func _respawn_player() -> void:
	var spawn: Marker2D = get_node_or_null("SpawnPoint")
	if spawn:
		player.global_position = spawn.global_position
	player.velocity = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if echo_cooldown > 0.0:
		echo_cooldown -= delta

	var r_down := Input.is_key_pressed(KEY_R)
	if r_down and not r_was_down:
		r_was_down = true
		if game_won:
			get_tree().change_scene_to_file(first_scene)
		else:
			get_tree().reload_current_scene()
		return
	r_was_down = r_down

	if game_won or changing_scene:
		return

	var vel: Vector2 = player.velocity
	if not player.is_on_floor():
		vel.y += gravity_force * delta

	var jump_pressed := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	if jump_pressed and player.is_on_floor():
		vel.y = jump_velocity

	var move_dir: float = 0.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_dir += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_dir -= 1.0

	if move_dir != 0.0:
		vel.x = move_dir * player_speed
		player_sprite.flip_h = move_dir < 0.0
	else:
		vel.x = move_toward(vel.x, 0.0, player_speed)

	if Input.is_key_pressed(KEY_E) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if echoes_left > 0 and echo_cooldown <= 0.0:
			_emit_echo()

	player.velocity = vel
	player.move_and_slide()

	if player.global_position.y > void_death_y:
		_die_and_create_corpse_platform()
	else:
		for i in player.get_slide_collision_count():
			var collider = player.get_slide_collision(i).get_collider()
			if collider and collider.is_in_group("hazard"):
				_die_and_create_corpse_platform()
				break

	_update_sonar_rays(delta)
	_update_fading_visuals(delta)
	overlay.queue_redraw()


func _emit_echo() -> void:
	echo_cooldown = 0.4
	echoes_left -= 1
	_update_hud()

	echo_rings.append({"pos": player.global_position, "radius": 10.0, "alpha": 1.0})

	for i in range(sonar_ray_count):
		var angle: float = (TAU / float(sonar_ray_count)) * float(i)
		sonar_rays.append({
			"pos": player.global_position,
			"dir": Vector2.RIGHT.rotated(angle),
			"bounces": sonar_bounces,
			"life": 1.3,
			"curve": sonar_curve * randf_range(0.8, 1.2),
			"points": [player.global_position],
		})


func _update_sonar_rays(delta: float) -> void:
	var space_state := get_world_2d().direct_space_state

	for i in range(sonar_rays.size() - 1, -1, -1):
		var ray: Dictionary = sonar_rays[i]
		ray["life"] -= delta
		if ray["life"] <= 0.0:
			sonar_rays.remove_at(i)
			continue

		ray["dir"] = (ray["dir"] as Vector2).rotated(ray["curve"] * delta)  # bend the path
		var start_pos: Vector2 = ray["pos"]
		var end_pos: Vector2 = start_pos + ray["dir"] * sonar_speed * delta

		var query := PhysicsRayQueryParameters2D.create(start_pos, end_pos, 2)
		var hit := space_state.intersect_ray(query)

		if hit:
			ray["points"].append(hit["position"])
			ray["pos"] = hit["position"] + hit["normal"] * 1.5
			_reveal_collider(hit["collider"])
			if ray["bounces"] > 0:
				ray["dir"] = (ray["dir"] as Vector2).bounce(hit["normal"])
				ray["bounces"] -= 1
			else:
				ray["life"] = min(ray["life"], 0.2)
		else:
			ray["pos"] = end_pos
			ray["points"].append(end_pos)

		while ray["points"].size() > 18:
			ray["points"].remove_at(0)


func _reveal_collider(collider: Object) -> void:
	if collider is Node:
		var spr = collider.get_node_or_null("Sprite2D")
		if spr:
			revealed_sprites[spr] = 1.0
			spr.modulate.a = 1.0


func _update_fading_visuals(delta: float) -> void:
	for spr in revealed_sprites.keys():
		if is_instance_valid(spr):
			var rest: float = 0.0
			if spr.get_parent().is_in_group("hazard"):
				rest = spike_rest_alpha
			var a: float = move_toward(revealed_sprites[spr], rest, delta * 0.48)
			spr.modulate.a = a
			if a <= rest:
				revealed_sprites.erase(spr)
			else:
				revealed_sprites[spr] = a
		else:
			revealed_sprites.erase(spr)

	for i in range(echo_rings.size() - 1, -1, -1):
		echo_rings[i]["radius"] += 480.0 * delta
		echo_rings[i]["alpha"] -= 2.1 * delta
		if echo_rings[i]["alpha"] <= 0.0:
			echo_rings.remove_at(i)


func _die_and_create_corpse_platform() -> void:
	var corpse := StaticBody2D.new()
	corpse.collision_layer = 2
	corpse.collision_mask = 1
	corpse.add_to_group("echo_surface")

	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(48, 16)
	col.shape = rect
	corpse.add_child(col)

	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	spr.texture = player_sprite.texture
	spr.scale = Vector2(1.5, 0.55)  # squished shrew
	spr.flip_h = player_sprite.flip_h
	spr.modulate = Color(0.85, 0.55, 1.0, 1.0)
	corpse.add_child(spr)

	add_child(corpse)
	var pos: Vector2 = player.global_position
	pos.y = min(pos.y, void_death_y - 20.0)  # void deaths leave a platform you can stand on
	corpse.global_position = pos
	corpse_platforms.append(corpse)
	revealed_sprites[spr] = 1.0

	_respawn_player()


func _on_exit_door_entered(body: Node2D) -> void:
	if body != player or game_won or changing_scene:
		return
	if next_scene != "":
		changing_scene = true
		get_tree().change_scene_to_file.call_deferred(next_scene)
	else:
		game_won = true
		hud_label.text = "YOU ESCAPED ALL %d ROUNDS!  |  Press [R] to play again" % total_rounds


func _on_overlay_draw() -> void:
	for ring in echo_rings:
		overlay.draw_arc(ring["pos"], ring["radius"], 0.0, TAU, 48, Color(0.15, 0.95, 1.0, ring["alpha"]), 2.5, true)
	for ray in sonar_rays:
		if ray["points"].size() >= 2:
			var a: float = clampf(ray["life"], 0.0, 1.0)
			overlay.draw_polyline(PackedVector2Array(ray["points"]), Color(0.15, 0.95, 1.0, a), 2.5, true)


func _create_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud_label = Label.new()
	hud_label.position = Vector2(20, 16)
	hud_label.add_theme_font_size_override("font_size", 20)
	hud_label.add_theme_color_override("font_color", Color(0.15, 0.95, 1.0))
	canvas.add_child(hud_label)


func _update_hud() -> void:
	if hud_label:
		hud_label.text = "ROUND %d / %d  |  ECHOES LEFT: %d  |  [E / Right-Click] Sonar  |  [R] Restart" % [round_number, total_rounds, echoes_left]


func _ensure_placeholder_texture(spr: Sprite2D, size: Vector2i, color: Color) -> void:
	if spr and spr.texture == null:
		var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		img.fill(color)
		spr.texture = ImageTexture.create_from_image(img)


# ==============================================================================
# CAVE LOOK: everything below is generated in code. Drag your own PNGs into any
# Sprite2D Texture box and these generated versions are skipped for that sprite.
# ==============================================================================

func _build_floor_spikes(hazards: Node) -> void:
	if hazards.has_node("FloorSpike0"):
		return
	var count: int = int(ceil(1152.0 / 32.0))
	for i in count:
		var body := StaticBody2D.new()
		body.name = "FloorSpike%d" % i
		body.collision_layer = 2
		body.collision_mask = 1
		body.position = Vector2(16 + i * 32, floor_spike_y)
		var col := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(28, 28)
		col.shape = rect
		body.add_child(col)
		var spr := Sprite2D.new()
		spr.name = "Sprite2D"
		body.add_child(spr)
		hazards.add_child(body)


func _dot(img: Image, cx: int, cy: int, r: float, color: Color) -> void:
	for y in range(cy - int(r) - 1, cy + int(r) + 2):
		for x in range(cx - int(r) - 1, cx + int(r) + 2):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				if Vector2(x - cx, y - cy).length() <= r:
					img.set_pixel(x, y, color)


func _make_shrew_texture() -> ImageTexture:
	var w := 32
	var h := 28
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var fur := Color(0.66, 0.58, 0.52)
	var fur_dark := Color(0.42, 0.36, 0.34)
	var belly := Color(0.86, 0.8, 0.74)
	# legs
	for lx in [9, 10, 11, 19, 20, 21]:
		for ly in range(23, 28):
			img.set_pixel(lx, ly, fur_dark)
	# tail
	for tx in range(0, 6):
		img.set_pixel(tx, 20 - (tx >> 1), fur_dark)
		img.set_pixel(tx, 21 - (tx >> 1), fur_dark)
	# body + snout
	for y in range(h):
		for x in range(w):
			var bx: float = (x - 14.0) / 12.0
			var by: float = (y - 17.0) / 9.0
			var d: float = bx * bx + by * by
			if d <= 1.0:
				var c: Color = fur if y < 18 else belly
				if d > 0.72:
					c = fur_dark
				img.set_pixel(x, y, c)
			if x >= 22 and x <= 31:
				var half: float = (31.0 - x) / 9.0 * 4.5 + 0.6
				if absf(y - 17.0) <= half:
					img.set_pixel(x, y, fur)
	# ear, eye, nose
	_dot(img, 11, 9, 3.2, fur_dark)
	_dot(img, 11, 9, 1.6, Color(0.9, 0.6, 0.6))
	_dot(img, 23, 15, 1.4, Color(1, 1, 1))
	_dot(img, 31, 17, 1.2, Color(1.0, 0.55, 0.65))
	return ImageTexture.create_from_image(img)


func _make_rock_texture(size: Vector2i, seed_val: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.09
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(size.x):
		var inset: float = maxf(0.0, 5.0 - float(mini(x, size.x - 1 - x)))
		var top: float = 2.0 + (noise.get_noise_1d(x) + 1.0) * 2.0 + inset
		var bottom: float = size.y - 2.0 - (noise.get_noise_1d(x + 500.0) + 1.0) * 3.5 - inset
		for y in range(size.y):
			if y >= top and y <= bottom:
				var v: float = 0.58 + rng.randf_range(-0.08, 0.08)
				if y < top + 2.0:
					v += 0.25
				elif y > bottom - 3.0:
					v -= 0.22
				if rng.randf() < 0.03:
					v -= 0.2
				img.set_pixel(x, y, Color(v, v * 0.97, v * 0.92))
	return ImageTexture.create_from_image(img)


func _make_spike_texture() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for s in range(2):
		var cx: int = 8 + s * 16
		for y in range(32):
			var half: float = (y / 31.0) * 8.0
			for x in range(int(cx - half), int(cx + half) + 1):
				if x >= 0 and x < 32:
					var v: float = 1.0 if absf(x - cx) > half - 1.5 else 0.85
					img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


func _make_door_texture() -> ImageTexture:
	var w := 36
	var h := 56
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(h):
		for x in range(w):
			var dx: float = (x - 17.5) / 18.0
			var dy: float = (y - 27.5) / 28.0
			var d: float = sqrt(dx * dx + dy * dy)
			if d <= 1.0:
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 - pow(d, 3.0)))
	return ImageTexture.create_from_image(img)


func _create_cave_background() -> void:
	var bg := Node2D.new()
	bg.z_index = -100
	bg.draw.connect(_on_bg_draw.bind(bg))
	add_child(bg)
	bg.queue_redraw()

	# drifting cave dust
	var dust := CPUParticles2D.new()
	dust.position = Vector2(576, 324)
	dust.z_index = -50
	dust.amount = 45
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(576, 324)
	dust.direction = Vector2(0, -1)
	dust.spread = 180.0
	dust.gravity = Vector2.ZERO
	dust.initial_velocity_min = 4.0
	dust.initial_velocity_max = 14.0
	dust.scale_amount_min = 1.5
	dust.scale_amount_max = 3.0
	dust.color = Color(0.5, 0.8, 0.9, 0.18)
	add_child(dust)


func _on_bg_draw(bg: Node2D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rock := Color(0.05, 0.055, 0.075)
	var rim := Color(0.09, 0.105, 0.14)
	# misty back wall
	for i in range(40):
		bg.draw_circle(Vector2(rng.randf_range(0, 1152), rng.randf_range(0, 648)), rng.randf_range(30, 90), Color(0.04, 0.05, 0.07, 0.5))
	# stalactites
	var x: float = -20.0
	while x < 1180.0:
		var w: float = rng.randf_range(30, 80)
		var h: float = rng.randf_range(25, 90)
		bg.draw_colored_polygon(PackedVector2Array([Vector2(x, -10), Vector2(x + w, -10), Vector2(x + w * 0.5, h)]), rock)
		bg.draw_polyline(PackedVector2Array([Vector2(x, -10), Vector2(x + w * 0.5, h), Vector2(x + w, -10)]), rim, 2.0)
		x += w * 0.8
	# stalagmites along the floor
	x = -20.0
	while x < 1180.0:
		var w2: float = rng.randf_range(30, 80)
		var h2: float = rng.randf_range(20, 70)
		bg.draw_colored_polygon(PackedVector2Array([Vector2(x, 670), Vector2(x + w2, 670), Vector2(x + w2 * 0.5, 648 - h2)]), rock)
		bg.draw_polyline(PackedVector2Array([Vector2(x, 670), Vector2(x + w2 * 0.5, 648 - h2), Vector2(x + w2, 670)]), rim, 2.0)
		x += w2 * 0.8
