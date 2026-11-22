extends "res://round_base.gd"

# Round 2: its own settings. Edit these numbers to tune this round.
func _init() -> void:
	round_number = 2
	echoes_for_round = 7
	next_scene = "res://round3.tscn"
