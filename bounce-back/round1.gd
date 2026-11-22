extends "res://round_base.gd"

# Round 1: its own settings. Edit these numbers to tune this round.
func _init() -> void:
	round_number = 1
	echoes_for_round = 5
	next_scene = "res://round2.tscn"
