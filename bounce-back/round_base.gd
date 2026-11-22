extends Node2D

# round_base.gd - all the game logic for ONE round scene.
# Each round (round1.tscn ... round5.tscn) has its own tiny script (round1.gd ...)
# that extends this file and sets its own numbers. Every round scene runs on its
# own: open it and press F6 (Run Current Scene). Press F5 to play from Round 1.

const WORLD_W: float = 1152.0
const WORLD_H: float = 648.0

@export var round_number: int = 1
@export var total_rounds: int = 5
@export var echoes_for_round: int = 5
@export var round_title: String = ""
@export_file("*.tscn") var next_scene: String = ""        # empty = last round
@export_file("*.tscn") var first_scene: String = "res://round1.tscn"

# --- movement ---
@export var player_speed: float = 260.0
@export var jump_velocity: float = -430.0
@export var gravity_force: float = 980.0
@export var void_death_y: float = 820.0
@export var exit_edge_x: float = 1148.0     # cross this x to leave the level

# --- sound wave (echo) ---
@export var sonar_speed: float = 520.0           # how fast the wave travels
@export var sonar_max_distance: float = 1500.0   # how far it goes (the whole cave)
@export var sonar_samples: int = 200             # smoothness / precision of the wavefront
@export var sonar_bounces: int = 2               # how many times it reflects off rock
@export var reveal_fade_speed: float = 1.7       # bigger = rock disappears faster after being hit

# --- hazards & bodies ---
@export var floor_spikes: bool = true
@export var floor_spike_y: float = 632.0
@export var spike_rest_alpha: float = 0.15       # how visible the gray FLOOR spikes stay
@export var max_bodies: int = 4                  # after this many bodies the next death crumbles them all

var player: CharacterBody2D
var player_sprite: Sprite2D
var echoes_left: int = 0
var echo_cooldown: float = 0.0
var game_won: bool = false
var r_was_down: bool = false
var changing_scene: bool = false
var deaths: int = 0

var revealed_sprites: Dictionary = {}
var waves: Array = []
var corpse_platforms: Array = []
var overlay: Node2D
var crystal_node: Node2D
var crystals: Array = []
var hud_line1: TextureRect
var ray_query: PhysicsRayQueryParameters2D
var sfx_ping: AudioStreamPlayer
var sfx_death: AudioStreamPlayer
var sfx_chime: AudioStreamPlayer

# 5x7 pixel font so all the text looks like an arcade game
const GLYPHS: Dictionary = {
	" ": ["00000","00000","00000","00000","00000","00000","00000"],
	"A": ["01110","10001","10001","11111","10001","10001","10001"],
	"B": ["11110","10001","10001","11110","10001","10001","11110"],
	"C": ["01110","10001","10000","10000","10000","10001","01110"],
	"D": ["11110","10001","10001","10001","10001","10001","11110"],
	"E": ["11111","10000","10000","11110","10000","10000","11111"],
	"F": ["11111","10000","10000","11110","10000","10000","10000"],
	"G": ["01110","10001","10000","10111","10001","10001","01111"],
	"H": ["10001","10001","10001","11111","10001","10001","10001"],
	"I": ["01110","00100","00100","00100","00100","00100","01110"],
	"J": ["00111","00010","00010","00010","00010","10010","01100"],
	"K": ["10001","10010","10100","11000","10100","10010","10001"],
	"L": ["10000","10000","10000","10000","10000","10000","11111"],
	"M": ["10001","11011","10101","10101","10001","10001","10001"],
	"N": ["10001","11001","10101","10011","10001","10001","10001"],
	"O": ["01110","10001","10001","10001","10001","10001","01110"],
	"P": ["11110","10001","10001","11110","10000","10000","10000"],
	"Q": ["01110","10001","10001","10001","10101","10010","01101"],
	"R": ["11110","10001","10001","11110","10100","10010","10001"],
	"S": ["01111","10000","10000","01110","00001","00001","11110"],
	"T": ["11111","00100","00100","00100","00100","00100","00100"],
	"U": ["10001","10001","10001","10001","10001","10001","01110"],
	"V": ["10001","10001","10001","10001","10001","01010","00100"],
	"W": ["10001","10001","10001","10101","10101","10101","01010"],
	"X": ["10001","10001","01010","00100","01010","10001","10001"],
	"Y": ["10001","10001","01010","00100","00100","00100","00100"],
	"Z": ["11111","00001","00010","00100","01000","10000","11111"],
	"0": ["01110","10001","10011","10101","11001","10001","01110"],
	"1": ["00100","01100","00100","00100","00100","00100","01110"],
	"2": ["01110","10001","00001","00010","00100","01000","11111"],
	"3": ["11110","00001","00001","01110","00001","00001","11110"],
	"4": ["00010","00110","01010","10010","11111","00010","00010"],
	"5": ["11111","10000","11110","00001","00001","10001","01110"],
	"6": ["00110","01000","10000","11110","10001","10001","01110"],
	"7": ["11111","00001","00010","00100","01000","01000","01000"],
	"8": ["01110","10001","10001","01110","10001","10001","01110"],
	"9": ["01110","10001","10001","01111","00001","00010","01100"],
	"/": ["00001","00001","00010","00100","01000","10000","10000"],
	":": ["00000","00100","00100","00000","00100","00100","00000"],
	"[": ["01110","01000","01000","01000","01000","01000","01110"],
	"]": ["01110","00010","00010","00010","00010","00010","01110"],
	"-": ["00000","00000","00000","11111","00000","00000","00000"],
	"!": ["00100","00100","00100","00100","00100","00000","00100"],
	".": ["00000","00000","00000","00000","00000","01100","01100"],
	",": ["00000","00000","00000","00000","01100","00100","01000"],
	">": ["10000","01000","00100","00010","00100","01000","10000"],
	"<": ["00001","00010","00100","01000","00100","00010","00001"],
	"|": ["00100","00100","00100","00100","00100","00100","00100"],
	"?": ["01110","10001","00001","00010","00100","00000","00100"],
	"+": ["00000","00100","00100","11111","00100","00100","00000"],
	"=": ["00000","00000","11111","00000","11111","00000","00000"],
	"'": ["00100","00100","01000","00000","00000","00000","00000"],
	"(": ["00010","00100","01000","01000","01000","00100","00010"],
	")": ["01000","00100","00010","00010","00010","00100","01000"],
}


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	_ensure_environment()
	_create_cave_background()
	overlay = Node2D.new()
	overlay.z_index = 10
	overlay.draw.connect(_on_overlay_draw)
	add_child(overlay)
	_create_player()
	_setup_round_objects()
	_create_audio()
	_create_hud()
	echoes_left = echoes_for_round
	_update_hud()
	_show_round_banner()


func _ensure_environment() -> void:
	for child in get_children():
		if child is WorldEnvironment:
			return
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.85
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
				var sz := Vector2i(120, 24)
				var cs = plat.get_node_or_null("CollisionShape2D")
				if cs and cs.shape is RectangleShape2D:
					sz = Vector2i(cs.shape.size)
				spr.texture = _make_rock_texture(sz, str(plat.name).hash())
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
		var is_floor: bool = str(haz.name).begins_with("FloorSpike")
		if is_floor:
			haz.add_to_group("floor_spike")
		var spr: Sprite2D = haz.get_node_or_null("Sprite2D")
		if spr and spr.texture == null:
			spr.texture = _make_spike_texture() if is_floor else _make_black_spike_texture()
		if spr:
			if is_floor:
				spr.modulate = Color(0.8, 0.82, 0.86, spike_rest_alpha)
			else:
				spr.modulate = Color(1, 1, 1, 0.0)  # black path spikes: hidden until the wave hits them

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
		_update_waves(delta)
		_update_fading_visuals(delta)
		overlay.queue_redraw()
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

	if player.global_position.x < 14.0:
		player.global_position.x = 14.0

	# Walk (or jump) off the right side of the screen to reach the next level
	if player.global_position.x > exit_edge_x:
		_finish_round()
		return

	if player.global_position.y > void_death_y:
		_die(null)
	else:
		for i in player.get_slide_collision_count():
			var collider = player.get_slide_collision(i).get_collider()
			if collider and collider.is_in_group("hazard"):
				_die(collider)
				break

	_update_waves(delta)
	_update_fading_visuals(delta)
	overlay.queue_redraw()
	if crystal_node:
		crystal_node.queue_redraw()


# ==============================================================================
# SOUND WAVE: a real wavefront that spreads through the cave, bounces off rock,
# is blocked by it (leaving shadows), and bends around platform corners.
# ==============================================================================

func _emit_echo() -> void:
	echo_cooldown = 0.45
	echoes_left -= 1
	_update_hud()
	sfx_ping.play()
	var origin: Vector2 = player.global_position
	var none: Array[RID] = []
	# the main pulse reveals rock; two weaker pulses trail behind it like a real echo
	_spawn_wave(origin, sonar_samples, 1.0, 0.0, true, sonar_max_distance, sonar_bounces, none, true)
	_spawn_wave(origin, int(sonar_samples * 0.5), 0.55, 0.13, false, sonar_max_distance, 1, none, true)
	_spawn_wave(origin, int(sonar_samples * 0.35), 0.3, 0.26, false, sonar_max_distance * 0.8, 1, none, true)


func _spawn_wave(origin: Vector2, n: int, amp: float, delay: float, reveals: bool, max_dist: float, bounces: int, exclude: Array[RID], primary: bool) -> void:
	var pos := PackedVector2Array()
	var dirs := PackedVector2Array()
	var alive := PackedByteArray()
	var gens := PackedInt32Array()
	var dists := PackedFloat32Array()
	for i in range(n):
		pos.append(origin)
		dirs.append(Vector2.RIGHT.rotated(TAU * float(i) / float(n)))
		alive.append(1)
		gens.append(0)
		dists.append(0.0)
	waves.append({
		"n": n, "amp": amp, "delay": delay, "reveals": reveals, "max_dist": max_dist,
		"bounces": bounces, "primary": primary, "exclude": exclude, "diffracted": {},
		"pos": pos, "dir": dirs, "alive": alive, "gen": gens, "dist": dists,
	})


func _update_waves(delta: float) -> void:
	if waves.is_empty():
		return
	var space := get_world_2d().direct_space_state
	if ray_query == null:
		ray_query = PhysicsRayQueryParameters2D.new()
		ray_query.collision_mask = 2
	var step: float = sonar_speed * delta

	for wi in range(waves.size() - 1, -1, -1):
		var w: Dictionary = waves[wi]
		if w["delay"] > 0.0:
			w["delay"] -= delta
			continue
		var pos: PackedVector2Array = w["pos"]
		var dirs: PackedVector2Array = w["dir"]
		var alive: PackedByteArray = w["alive"]
		var gens: PackedInt32Array = w["gen"]
		var dists: PackedFloat32Array = w["dist"]
		var n: int = w["n"]
		var max_dist: float = w["max_dist"]
		var bounces: int = w["bounces"]
		var amp: float = w["amp"]
		var reveals: bool = w["reveals"]
		var primary: bool = w["primary"]
		var any_alive: bool = false
		ray_query.exclude = w["exclude"]

		for i in range(n):
			if alive[i] == 0:
				continue
			var a: Vector2 = pos[i]
			var b: Vector2 = a + dirs[i] * step
			ray_query.from = a
			ray_query.to = b
			var hit := space.intersect_ray(ray_query)
			if hit.is_empty():
				pos[i] = b
				dists[i] += step
			else:
				var hp: Vector2 = hit["position"]
				var nrm: Vector2 = hit["normal"]
				dists[i] += a.distance_to(hp)
				pos[i] = hp + nrm * 1.5
				if reveals:
					var strength: float = amp * pow(0.65, gens[i]) * (1.0 - 0.4 * dists[i] / max_dist)
					_reveal_collider(hit["collider"], strength)
					if primary:
						_try_diffract(hit["collider"], w)
				if gens[i] < bounces:
					dirs[i] = dirs[i].bounce(nrm)
					gens[i] += 1
				else:
					alive[i] = 0
			if dists[i] >= max_dist:
				alive[i] = 0
			if alive[i] == 1:
				any_alive = true

		if not any_alive:
			waves.remove_at(wi)


# Diffraction: the first time the main wave touches a platform, small wavelets spill
# out of its top corners, so sound bends around edges instead of only bouncing.
func _try_diffract(collider: Object, w: Dictionary) -> void:
	if not (collider is StaticBody2D):
		return
	if not collider.is_in_group("echo_surface"):
		return
	var done: Dictionary = w["diffracted"]
	var id: int = collider.get_instance_id()
	if done.has(id):
		return
	done[id] = true
	var cs = collider.get_node_or_null("CollisionShape2D")
	if cs == null or not (cs.shape is RectangleShape2D):
		return
	var sz: Vector2 = cs.shape.size
	var c: Vector2 = collider.global_position
	var ex: Array[RID] = [collider.get_rid()]
	for sx in [-1.0, 1.0]:
		var corner: Vector2 = c + Vector2(sx * (sz.x * 0.5 + 3.0), -sz.y * 0.5 - 3.0)
		_spawn_wave(corner, 28, 0.45, 0.0, true, 190.0, 0, ex, false)


func _reveal_collider(collider: Object, intensity: float) -> void:
	if collider is Node:
		var spr = collider.get_node_or_null("Sprite2D")
		if spr:
			var cur: float = revealed_sprites.get(spr, 0.0)
			var v: float = maxf(cur, clampf(intensity, 0.0, 1.0))
			revealed_sprites[spr] = v
			spr.modulate.a = maxf(v, spr.modulate.a)


func _update_fading_visuals(delta: float) -> void:
	for spr in revealed_sprites.keys():
		if is_instance_valid(spr):
			var rest: float = 0.0
			if spr.get_parent().is_in_group("floor_spike"):
				rest = spike_rest_alpha
			var a: float = move_toward(revealed_sprites[spr], rest, delta * reveal_fade_speed)
			spr.modulate.a = a
			if a <= rest:
				revealed_sprites.erase(spr)
			else:
				revealed_sprites[spr] = a
		else:
			revealed_sprites.erase(spr)


func _on_overlay_draw() -> void:
	for w in waves:
		if w["delay"] > 0.0:
			continue
		var pos: PackedVector2Array = w["pos"]
		var alive: PackedByteArray = w["alive"]
		var gens: PackedInt32Array = w["gen"]
		var dists: PackedFloat32Array = w["dist"]
		var n: int = w["n"]
		var max_dist: float = w["max_dist"]
		var amp: float = w["amp"]
		var step_ang: float = TAU / float(n)
		var line := PackedVector2Array()
		var line_alpha: float = 0.0
		for i in range(n + 1):
			var idx: int = i % n
			if alive[idx] == 0:
				_flush_wave_line(line, w, line_alpha)
				line = PackedVector2Array()
				continue
			if line.size() > 0:
				var prev: int = (i - 1 + n) % n
				var gap: float = pos[idx].distance_to(pos[prev])
				var limit: float = maxf(14.0, dists[idx] * step_ang * 2.6 + 8.0)
				if gens[idx] != gens[prev] or gap > limit:
					_flush_wave_line(line, w, line_alpha)
					line = PackedVector2Array()
			line.append(pos[idx])
			line_alpha = amp * pow(0.7, gens[idx]) * clampf(1.0 - dists[idx] / max_dist, 0.0, 1.0)
		_flush_wave_line(line, w, line_alpha)


func _flush_wave_line(line: PackedVector2Array, w: Dictionary, alpha: float) -> void:
	if line.size() < 2:
		return
	var main_w: float = 2.6 if w["primary"] else 1.6
	overlay.draw_polyline(line, Color(0.3, 0.95, 1.0, alpha * 0.16), main_w * 3.2, true)
	overlay.draw_polyline(line, Color(0.6, 1.0, 1.0, alpha), main_w, true)


# ==============================================================================
# DEATH, BODIES, ROUND PROGRESSION
# ==============================================================================

func _die(killer: Object) -> void:
	deaths += 1
	sfx_death.play()
	_burst(player.global_position, Color(0.85, 0.55, 1.0), 26)
	if killer != null:
		_reveal_collider(killer, 1.0)  # show what killed you

	# too many bodies: the cave collapses them all, only the newest stays
	if corpse_platforms.size() >= max_bodies:
		_crumble_bodies()
	_make_corpse()

	# every death refills your echoes
	echoes_left = echoes_for_round
	echo_cooldown = 0.0
	waves.clear()
	_update_hud()
	_respawn_player()


func _make_corpse() -> void:
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
	pos.y = min(pos.y, void_death_y - 20.0)
	corpse.global_position = pos
	corpse_platforms.append(corpse)
	revealed_sprites[spr] = 1.0


func _crumble_bodies() -> void:
	for corpse in corpse_platforms:
		if is_instance_valid(corpse):
			_burst(corpse.global_position, Color(0.6, 0.55, 0.65), 14)
			corpse.queue_free()
	corpse_platforms.clear()


func _burst(pos: Vector2, color: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 5
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.7
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 220.0
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


func _finish_round() -> void:
	if game_won or changing_scene:
		return
	changing_scene = true
	sfx_chime.play()
	var target: String = next_scene
	if target == "" and round_number < total_rounds:
		target = "res://round%d.tscn" % (round_number + 1)
	if target != "":
		await get_tree().create_timer(0.35).timeout
		get_tree().change_scene_to_file(target)
	else:
		game_won = true
		_show_win_screen()


# ==============================================================================
# PIXEL-FONT UI
# ==============================================================================

func _make_pixel_text(text: String, color: Color) -> ImageTexture:
	var lines: PackedStringArray = text.to_upper().split("\n")
	var cols: int = 1
	for l in lines:
		cols = maxi(cols, l.length())
	var img := Image.create(cols * 6 + 2, lines.size() * 9 + 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var shadow := Color(0.0, 0.08, 0.12, 0.95)
	for pass_index in range(2):
		for li in range(lines.size()):
			var line: String = lines[li]
			for ci in range(line.length()):
				var g: Array = GLYPHS.get(line.substr(ci, 1), GLYPHS[" "])
				for row in range(7):
					var bits: String = g[row]
					for col in range(5):
						if bits[col] == "1":
							var px: int = ci * 6 + col
							var py: int = li * 9 + row
							if pass_index == 0:
								img.set_pixel(px + 1, py + 1, shadow)
							else:
								img.set_pixel(px, py, color)
	return ImageTexture.create_from_image(img)


func _add_pixel_label(parent: Node, text: String, color: Color, pixel_scale: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _make_pixel_text(text, color)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_KEEP
	tr.scale = Vector2(pixel_scale, pixel_scale)
	parent.add_child(tr)
	return tr


func _center_label(tr: TextureRect, y: float) -> void:
	var size_px: Vector2 = Vector2(tr.texture.get_size()) * tr.scale
	tr.position = Vector2((WORLD_W - size_px.x) * 0.5, y)


func _create_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud_line1 = _add_pixel_label(canvas, "", Color(0.4, 1.0, 1.0), 3.0)
	hud_line1.position = Vector2(18, 14)
	var l2 := _add_pixel_label(canvas, "[E / RIGHT CLICK] ECHO   [R] RESTART   [A D / ARROWS] MOVE   [SPACE] JUMP", Color(0.75, 0.85, 0.92), 2.0)
	l2.position = Vector2(18, 53)
	var l3 := _add_pixel_label(canvas, "WALK OFF THE RIGHT EDGE TO ESCAPE", Color(0.55, 1.0, 0.7), 2.0)
	l3.position = Vector2(18, 79)


func _update_hud() -> void:
	if hud_line1:
		hud_line1.texture = _make_pixel_text("ROUND %d/%d   ECHOES %d   BODIES %d/%d" % [round_number, total_rounds, echoes_left, corpse_platforms.size(), max_bodies], Color(0.4, 1.0, 1.0))


func _show_round_banner() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	var root := Control.new()
	canvas.add_child(root)
	var big := _add_pixel_label(root, "ROUND %d" % round_number, Color(0.4, 1.0, 1.0), 10.0)
	_center_label(big, 210.0)
	if round_title != "":
		var sub := _add_pixel_label(root, round_title, Color(0.9, 0.95, 1.0), 4.0)
		_center_label(sub, 340.0)
	var tw := create_tween()
	tw.tween_interval(1.1)
	tw.tween_property(root, "modulate:a", 0.0, 0.9)
	tw.tween_callback(canvas.queue_free)


func _show_win_screen() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)
	# giant pixel text that fills the whole screen
	var big := _add_pixel_label(canvas, "YOU\nESCAPED\nTHE CAVE!", Color(0.4, 1.0, 1.0), 1.0)
	var tex_size: Vector2 = big.texture.get_size()
	var s: float = floorf(minf(WORLD_W * 0.94 / tex_size.x, WORLD_H * 0.8 / tex_size.y))
	big.scale = Vector2(s, s)
	big.position = Vector2((WORLD_W - tex_size.x * s) * 0.5, 10.0)
	var small := _add_pixel_label(canvas, "PRESS [R] TO PLAY AGAIN", Color(1, 1, 1), 5.0)
	_center_label(small, WORLD_H - 70.0)


# ==============================================================================
# SOUND EFFECTS (generated in code, no audio files needed)
# ==============================================================================

func _make_stream(samples: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st


func _create_audio() -> void:
	var rate: int = 22050
	# ping: a falling chirp with two softer echoes
	var n: int = rate
	var base := PackedFloat32Array()
	base.resize(n)
	var phase: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(rate)
		var f: float = 380.0 + 900.0 * exp(-6.0 * t)
		phase += TAU * f / float(rate)
		base[i] = sin(phase) * exp(-7.0 * t) * 0.6
	var ping := PackedFloat32Array()
	ping.resize(n)
	for i in range(n):
		var v: float = base[i]
		var d1: int = int(0.2 * rate)
		var d2: int = int(0.42 * rate)
		if i >= d1:
			v += base[i - d1] * 0.4
		if i >= d2:
			v += base[i - d2] * 0.2
		ping[i] = v
	sfx_ping = _make_player(_make_stream(ping, rate), -9.0)

	# death: low thump with noise
	var dn: int = int(0.45 * rate)
	var death := PackedFloat32Array()
	death.resize(dn)
	for i in range(dn):
		var t: float = float(i) / float(rate)
		death[i] = (sin(TAU * 70.0 * t) * 0.7 + randf_range(-1.0, 1.0) * 0.4) * exp(-9.0 * t)
	sfx_death = _make_player(_make_stream(death, rate), -6.0)

	# chime: little rising arpeggio
	var notes: Array = [523.0, 659.0, 784.0, 1046.0]
	var cn: int = int(0.6 * rate)
	var chime := PackedFloat32Array()
	chime.resize(cn)
	for k in range(notes.size()):
		var start: int = int(float(k) * 0.09 * rate)
		for i in range(start, cn):
			var t: float = float(i - start) / float(rate)
			chime[i] += sin(TAU * float(notes[k]) * t) * exp(-6.0 * t) * 0.3
	sfx_chime = _make_player(_make_stream(chime, rate), -8.0)


func _make_player(stream: AudioStream, volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume
	add_child(p)
	return p


# ==============================================================================
# CAVE BACKGROUND (all generated in code)
# ==============================================================================

func _create_cave_background() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + round_number * 37

	var holder := Node2D.new()
	holder.z_index = -100
	add_child(holder)

	# rock wall: big soft noise plus a fine cellular "stone" grain
	var n1 := FastNoiseLite.new()
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.frequency = 0.005
	n1.fractal_octaves = 4
	n1.seed = 11 * round_number
	var wall := Sprite2D.new()
	wall.centered = false
	wall.texture = ImageTexture.create_from_image(n1.get_image(int(WORLD_W), int(WORLD_H)))
	wall.modulate = Color(0.2, 0.19, 0.25)
	holder.add_child(wall)

	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_CELLULAR
	n2.frequency = 0.03
	n2.seed = 7 * round_number + 3
	var grain := Sprite2D.new()
	grain.centered = false
	grain.texture = ImageTexture.create_from_image(n2.get_image(int(WORLD_W), int(WORLD_H)))
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	grain.material = add_mat
	grain.modulate = Color(0.045, 0.05, 0.065)
	holder.add_child(grain)

	# stalactites, stalagmites and the left cave wall in three depth layers
	var sil := Node2D.new()
	sil.z_index = -95
	sil.draw.connect(_draw_cave_silhouettes.bind(sil, 500 + round_number * 13))
	add_child(sil)

	# dark vignette so the edges of the cave fade into blackness
	var vimg := Image.create(64, 36, false, Image.FORMAT_RGBA8)
	for y in range(36):
		for x in range(64):
			var dx: float = (x - 31.5) / 32.0
			var dy: float = (y - 17.5) / 18.0
			var d: float = sqrt(dx * dx + dy * dy * 1.1)
			vimg.set_pixel(x, y, Color(0, 0, 0, clampf(pow(d, 2.4) * 0.85, 0.0, 0.92)))
	var vig := Sprite2D.new()
	vig.centered = false
	vig.texture = ImageTexture.create_from_image(vimg)
	vig.scale = Vector2(WORLD_W / 64.0, WORLD_H / 36.0)
	vig.z_index = -60
	add_child(vig)

	# glowing crystals on the ceiling and left wall
	var palette: Array = [Color(0.2, 0.9, 0.85), Color(0.6, 0.45, 1.0), Color(0.3, 0.65, 1.0)]
	for i in range(14):
		var p: Vector2
		if i < 8:
			p = Vector2(rng.randf_range(90.0, 1060.0), rng.randf_range(14.0, 46.0))
		else:
			p = Vector2(rng.randf_range(14.0, 34.0), rng.randf_range(130.0, 560.0))
		crystals.append({"pos": p, "col": palette[i % 3], "size": rng.randf_range(4.0, 8.0), "phase": rng.randf_range(0.0, TAU)})
	crystal_node = Node2D.new()
	crystal_node.z_index = -55
	crystal_node.draw.connect(_on_crystal_draw)
	add_child(crystal_node)

	# drifting dust
	var dust := CPUParticles2D.new()
	dust.position = Vector2(WORLD_W * 0.5, WORLD_H * 0.5)
	dust.z_index = -50
	dust.amount = 50
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(WORLD_W * 0.5, WORLD_H * 0.5)
	dust.direction = Vector2(0, -1)
	dust.spread = 180.0
	dust.gravity = Vector2.ZERO
	dust.initial_velocity_min = 4.0
	dust.initial_velocity_max = 14.0
	dust.scale_amount_min = 1.5
	dust.scale_amount_max = 3.0
	dust.color = Color(0.55, 0.8, 0.9, 0.16)
	add_child(dust)

	# water drips falling from the ceiling
	var drips := CPUParticles2D.new()
	drips.position = Vector2(WORLD_W * 0.5, -6.0)
	drips.z_index = -50
	drips.amount = 6
	drips.lifetime = 3.4
	drips.preprocess = 3.4
	drips.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	drips.emission_rect_extents = Vector2(WORLD_W * 0.5, 2.0)
	drips.direction = Vector2(0, 1)
	drips.spread = 0.0
	drips.gravity = Vector2(0, 420)
	drips.initial_velocity_min = 0.0
	drips.initial_velocity_max = 0.0
	drips.scale_amount_min = 1.5
	drips.scale_amount_max = 2.4
	drips.color = Color(0.6, 0.85, 1.0, 0.5)
	add_child(drips)


func _draw_cave_silhouettes(sil: Node2D, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	# drifting mist
	for i in range(34):
		sil.draw_circle(Vector2(rng.randf_range(0.0, WORLD_W), rng.randf_range(0.0, WORLD_H)), rng.randf_range(30.0, 95.0), Color(0.05, 0.06, 0.085, 0.45))
	# layers: [fill, rim, count, min height, max height]
	var layers: Array = [
		[Color(0.10, 0.11, 0.15), Color(0.17, 0.19, 0.25), 16, 40.0, 150.0],
		[Color(0.065, 0.07, 0.095), Color(0.12, 0.14, 0.19), 14, 30.0, 120.0],
		[Color(0.035, 0.04, 0.055), Color(0.08, 0.10, 0.14), 11, 25.0, 95.0],
	]
	for layer in layers:
		_draw_spikes(sil, rng, layer, -12.0, 1.0, 1.0)
		_draw_spikes(sil, rng, layer, WORLD_H + 12.0, -1.0, 0.5)
	# solid rock bands along the top and bottom
	sil.draw_rect(Rect2(-20.0, -30.0, WORLD_W + 40.0, 44.0), Color(0.03, 0.033, 0.045))
	sil.draw_rect(Rect2(-20.0, WORLD_H - 4.0, WORLD_W + 40.0, 60.0), Color(0.03, 0.033, 0.045))
	# jagged left cave wall (the right side stays open: that is the way out)
	var wall := PackedVector2Array([Vector2(-20.0, -20.0)])
	var y: float = -20.0
	while y < WORLD_H + 40.0:
		wall.append(Vector2(8.0 + rng.randf_range(0.0, 34.0), y))
		y += 38.0
	wall.append(Vector2(-20.0, WORLD_H + 40.0))
	sil.draw_colored_polygon(wall, Color(0.03, 0.035, 0.048))
	sil.draw_polyline(wall.slice(1, wall.size() - 1), Color(0.09, 0.11, 0.15), 2.0)
	# a very faint haze where the tunnel continues to the right
	for i in range(6):
		sil.draw_rect(Rect2(WORLD_W - 26.0 * float(i + 1), 0.0, 26.0, WORLD_H), Color(0.3, 0.7, 0.8, 0.012 * float(6 - i)))


func _draw_spikes(sil: Node2D, rng: RandomNumberGenerator, layer: Array, base_y: float, dir: float, hscale: float) -> void:
	var col: Color = layer[0]
	var rim: Color = layer[1]
	var count: int = layer[2]
	var hmin: float = layer[3]
	var hmax: float = layer[4]
	for i in range(count):
		var x: float = rng.randf_range(-30.0, WORLD_W + 10.0)
		var w: float = rng.randf_range(36.0, 110.0)
		var h: float = lerpf(hmin, hmax, pow(rng.randf(), 1.8)) * hscale
		var tip_x: float = x + rng.randf_range(-8.0, 8.0)
		var pts := PackedVector2Array([
			Vector2(x - w * 0.5, base_y),
			Vector2(x - w * 0.34, base_y + dir * h * 0.45),
			Vector2(tip_x, base_y + dir * h),
			Vector2(x + w * 0.3, base_y + dir * h * 0.5),
			Vector2(x + w * 0.5, base_y),
		])
		sil.draw_colored_polygon(pts, col)
		sil.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), rim, 1.5)


func _on_crystal_draw() -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	for c in crystals:
		var pulse: float = 0.65 + 0.35 * sin(t * 1.7 + float(c["phase"]))
		var col: Color = c["col"]
		var p: Vector2 = c["pos"]
		var s: float = c["size"]
		crystal_node.draw_circle(p, s * 6.0, Color(col.r, col.g, col.b, 0.04 * pulse))
		crystal_node.draw_circle(p, s * 3.0, Color(col.r, col.g, col.b, 0.09 * pulse))
		var pts := PackedVector2Array([
			p + Vector2(0.0, -s * 1.6), p + Vector2(s * 0.7, -s * 0.2), p + Vector2(s * 0.5, s),
			p + Vector2(-s * 0.5, s), p + Vector2(-s * 0.7, -s * 0.2),
		])
		crystal_node.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.5 + 0.4 * pulse))


# ==============================================================================
# GENERATED SPRITES (drag your own PNGs into any Sprite2D Texture box to replace)
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


func _make_black_spike_texture() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for s in range(2):
		var cx: int = 8 + s * 16
		for y in range(32):
			var half: float = (y / 31.0) * 8.0
			for x in range(int(cx - half), int(cx + half) + 1):
				if x >= 0 and x < 32:
					var edge: bool = absf(x - cx) > half - 1.5 or y < 2
					var v: float = 0.85 if edge else 0.02
					img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)
