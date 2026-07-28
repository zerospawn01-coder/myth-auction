extends SceneTree

func _init():
	print("Preloading case_package_validator.gd...")
	var scr = load("res://scripts/mvp/case_package_validator.gd")
	print("Script loaded: ", scr)
	if scr != null:
		var inst = scr.new()
		print("Instance: ", inst)
	quit(0)
