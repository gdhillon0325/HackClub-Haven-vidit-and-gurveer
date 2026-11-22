extends "res://round_base.gd"

# Round 4: its own settings. Edit these numbers to tune this round.
func _init() -> void:
	round_number = 4
	round_title = "BONE MAZE"
	echoes_for_round = 7
	next_scene = "res://round5.tscn"
