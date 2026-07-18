extends Node2D

const Sim = preload("res://sim.gd")
const GpuSim = preload("res://gpu_sim.gd")
const UI = preload("res://ui.gd")

const DEFAULT_SEED := 7
const PARTICLE_SIZE := 11.0

var sim # Sim or GpuSim (same API)
var mm: MultiMesh
var palette := PackedColorArray()
var paused := false
var substeps := 1
var ui: UI
var fps_label: Label
var presets: Array = [] # [{name, data}]
var hand_strength := 9000.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.045))
	get_window().title = "Primordial Dish"
	sim = GpuSim.new() if GpuSim.is_supported() else Sim.new()
	sim.world_size = get_viewport_rect().size
	sim.configure(2400, 5, DEFAULT_SEED)
	sim.randomize_matrix()
	_build_palette()
	_build_multimesh()
	_build_ui()
	_scan_presets()
	if presets.size() > 0:
		load_preset_index(0)
	_refresh_colors()
	_refresh_multimesh()


func _build_palette() -> void:
	palette.clear()
	for i in sim.num_species:
		palette.append(Color.from_hsv(float(i) / sim.num_species, 0.75, 1.0))


func _build_multimesh() -> void:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	var c := Vector2(23.5, 23.5)
	for y in 48:
		for x in 48:
			var d := (Vector2(x, y) - c).length() / 24.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	var quad := QuadMesh.new()
	quad.size = Vector2(PARTICLE_SIZE, PARTICLE_SIZE)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = sim.num_particles
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = mm
	mmi.texture = tex
	mmi.material = mat
	add_child(mmi)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = UI.new()
	layer.add_child(ui)
	ui.build(self)


func _physics_process(_delta: float) -> void:
	_handle_actions()
	if not paused:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			sim.apply_radial(get_global_mouse_position(), 170.0, hand_strength)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			sim.apply_radial(get_global_mouse_position(), 170.0, -hand_strength)
		elif Input.is_action_pressed("pl_stir"):
			sim.apply_radial(sim.world_size * 0.5, 500.0, hand_strength * 0.6)
		for s in substeps:
			sim.step()
		sim.fetch_positions()
		_refresh_multimesh()
	if fps_label:
		fps_label.text = "FPS %d | %d particles | K=%d%s" % [
			Engine.get_frames_per_second(), sim.num_particles, sim.num_species,
			"  [PAUSED]" if paused else ""]


func _handle_actions() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		return
	if Input.is_action_just_pressed("pl_pause"):
		paused = not paused
	if Input.is_action_just_pressed("pl_snapshot"):
		snapshot_preset()
	if Input.is_action_just_pressed("pl_randomize"):
		randomize_matrix()
	if Input.is_action_just_pressed("pl_mutate"):
		mutate_matrix()
	for i in 5:
		if Input.is_action_just_pressed("pl_preset%d" % (i + 1)):
			load_preset_index(i)
	if Input.is_action_just_pressed("pl_shot"):
		save_screenshot()
	if Input.is_action_just_pressed("pl_faster"):
		substeps = mini(substeps + 1, 5)
	if Input.is_action_just_pressed("pl_slower"):
		substeps = maxi(substeps - 1, 1)


func _refresh_colors() -> void:
	for i in sim.num_particles:
		mm.set_instance_color(i, palette[sim.species[i]])


func _refresh_multimesh() -> void:
	for i in sim.num_particles:
		mm.set_instance_transform_2d(i, Transform2D(0.0, sim.pos[i]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		sim.world_size = get_viewport_rect().size


func _exit_tree() -> void:
	if sim and sim.has_method("shutdown"):
		sim.shutdown()


# ---- called by the UI ----

func set_param(key: String, value: float) -> void:
	match key:
		"force_factor":
			sim.force_factor = value
		"rmax":
			sim.rmax = value
		"beta":
			sim.beta = value
		"damping":
			sim.damping = value
		"substeps":
			substeps = int(value)


func set_species(k: int) -> void:
	sim.configure(sim.num_particles, k, sim.rng.seed)
	sim.randomize_matrix()
	_build_palette()
	mm.instance_count = sim.num_particles
	_refresh_colors()
	_refresh_multimesh()
	ui.rebuild_matrix_grid()
	ui.update_matrix_grid()


func set_matrix_at(i: int, v: float) -> void:
	sim.set_matrix_at(i, v)


func randomize_matrix() -> void:
	sim.randomize_matrix()
	ui.update_matrix_grid()


func mutate_matrix() -> void:
	sim.mutate_matrix()
	ui.update_matrix_grid()


func zero_matrix() -> void:
	for i in sim.matrix.size():
		sim.matrix[i] = 0.0
	ui.update_matrix_grid()


func save_preset(pname: String) -> void:
	pname = pname.strip_edges()
	if pname == "":
		pname = "preset_%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute("user://presets")
	var d: Dictionary = sim.to_dict()
	d["name"] = pname
	var f := FileAccess.open("user://presets/%s.json" % pname.validate_filename(), FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	_scan_presets()


func load_preset_index(i: int) -> void:
	if i < 0 or i >= presets.size():
		return
	sim.apply_dict(presets[i].data)
	_build_palette()
	mm.instance_count = sim.num_particles
	_refresh_colors()
	_refresh_multimesh()
	ui.sync_from_sim()


func save_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute("res://screenshots")
	var img := get_viewport().get_texture().get_image()
	var path := "res://screenshots/shot_%d.png" % int(Time.get_unix_time_from_system())
	img.save_png(path)
	print("screenshot saved: ", path)


func snapshot_preset() -> void:
	DirAccess.make_dir_recursive_absolute("res://presets")
	var d: Dictionary = sim.to_dict()
	d["name"] = "snap_%d" % int(Time.get_unix_time_from_system())
	var path := "res://presets/%s.json" % d["name"]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	print("snapshot saved: ", path)
	_scan_presets()


func _scan_presets() -> void:
	presets.clear()
	for dir_path in ["res://presets", "user://presets"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for fname in dir.get_files():
			if not fname.ends_with(".json"):
				continue
			var d = JSON.parse_string(FileAccess.get_file_as_string(dir_path + "/" + fname))
			if d is Dictionary:
				presets.append({"name": d.get("name", fname.get_basename()), "data": d})
	if ui:
		var names := PackedStringArray()
		for p in presets:
			names.append(p.name)
		ui.refresh_presets(names)
