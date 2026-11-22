extends "res://round_base.gd"

# Round 3: its own settings. Edit these numbers to tune this round.
func _init() -> void:
	round_number = 3
	echoes_for_round = 8
	next_scene = "res://round4.tscn"
