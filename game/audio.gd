extends Node
## Autoload "Audio": efectos (2D y 3D, con variantes aleatorias), bucles pegados a un nodo, música con
## fundido cruzado, ambiente y sonidos de interfaz (se enganchan solos a todos los botones).
##
## Los efectos están en assets/audio/sfx/ con nombres "base_N.ogg": `play("hit_light")` elige una variante.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const AMBIENCE_DIR := "res://assets/audio/ambience/"
const POOL_3D := 24
const POOL_2D := 10

var _sounds := {}  ## base -> Array[AudioStream]
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _music_on := 0
var _music_name := ""
var _ambience: AudioStreamPlayer
var _ambience_name := ""
var _last_hover := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for f in ResourceLoader.list_directory(SFX_DIR):
		if not f.ends_with(".ogg"):
			continue
		var base := f.get_basename()
		var parts := base.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			base = parts[0]
		if not _sounds.has(base):
			_sounds[base] = []
		_sounds[base].append(load(SFX_DIR + f))
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.unit_size = 9.0
		p.max_distance = 70.0
		p.attenuation_filter_cutoff_hz = 9000.0
		p.attenuation_filter_db = -12.0
		add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool2d.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = &"Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = &"Ambience"
	add_child(_ambience)
	get_tree().node_added.connect(_on_node_added)


func has_sound(name: String) -> bool:
	return _sounds.has(name)


func _pick(name: String) -> AudioStream:
	var list: Array = _sounds.get(name, [])
	return list.pick_random() if not list.is_empty() else null


## Efecto en una posición del mundo (o sin posición si `pos` es INF).
func play(name: String, pos := Vector3.INF, volume_db := 0.0, pitch := 1.0, pitch_random := 0.08) -> void:
	var stream := _pick(name)
	if stream == null:
		return
	var p := pitch * (1.0 + randf_range(-pitch_random, pitch_random))
	if pos == Vector3.INF:
		var pl := _free2d()
		pl.bus = &"SFX"
		pl.stream = stream
		pl.volume_db = volume_db
		pl.pitch_scale = p
		pl.play()
		return
	var pl := _free3d()
	pl.stream = stream
	pl.volume_db = volume_db
	pl.pitch_scale = p
	pl.global_position = pos
	pl.play()


func play_ui(name: String, volume_db := -4.0) -> void:
	var stream := _pick(name)
	if stream == null:
		return
	var pl := _free2d()
	pl.bus = &"UI"
	pl.stream = stream
	pl.volume_db = volume_db
	pl.pitch_scale = 1.0
	pl.play()


## Bucle pegado a un nodo 3D (lanzallamas, brasero). Devuelve el reproductor para pararlo/liberarlo.
func attach_loop(name: String, parent: Node3D, volume_db := 0.0, bus := &"SFX") -> AudioStreamPlayer3D:
	var stream := _pick(name)
	if stream == null:
		stream = _load_loop(name)
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis and not (stream as AudioStreamOggVorbis).loop:
		stream = stream.duplicate()
		(stream as AudioStreamOggVorbis).loop = true
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = volume_db
	p.unit_size = 6.0
	p.max_distance = 40.0
	p.autoplay = true
	parent.add_child(p)
	return p


func _load_loop(name: String) -> AudioStream:
	var path := AMBIENCE_DIR + name + ".ogg"
	return load(path) if ResourceLoader.exists(path) else null


func music(name: String, fade := 1.5) -> void:
	if name == _music_name:
		return
	_music_name = name
	var old := _music[_music_on]
	_music_on = 1 - _music_on
	var new := _music[_music_on]
	var tw := create_tween().set_parallel()
	tw.tween_property(old, "volume_db", -80.0, fade)
	if name != "":
		new.stream = load(MUSIC_DIR + name + ".ogg")
		new.volume_db = -40.0
		new.play()
		tw.tween_property(new, "volume_db", 0.0, fade)
	tw.chain().tween_callback(old.stop)


## Pieza corta (victoria, derrota) por encima de la música, que baja mientras suena.
func stinger(name: String) -> void:
	var pl := _free2d()
	pl.bus = &"Music"
	pl.stream = load(MUSIC_DIR + name + ".ogg")
	pl.volume_db = 0.0
	pl.pitch_scale = 1.0
	pl.play()
	var cur := _music[_music_on]
	var tw := create_tween()
	tw.tween_property(cur, "volume_db", -18.0, 0.3)
	tw.tween_interval(4.0)
	tw.tween_property(cur, "volume_db", 0.0, 2.0)


func ambience(name: String, volume_db := 0.0) -> void:
	if name == _ambience_name:
		if name != "":
			create_tween().tween_property(_ambience, "volume_db", volume_db, 1.5)
		return
	_ambience_name = name
	if name == "":
		_ambience.stop()
		return
	_ambience.stream = load(AMBIENCE_DIR + name + ".ogg")
	_ambience.volume_db = volume_db
	_ambience.play()


func _free3d() -> AudioStreamPlayer3D:
	for p in _pool3d:
		if not p.playing:
			return p
	return _pool3d[0]


func _free2d() -> AudioStreamPlayer:
	for p in _pool2d:
		if not p.playing:
			return p
	return _pool2d[0]


# --- Interfaz -------------------------------------------------------------------------------

func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var b := n as BaseButton
		b.mouse_entered.connect(_on_hover.bind(b))
		b.focus_entered.connect(_on_hover.bind(b))
		b.pressed.connect(func() -> void: play_ui("ui_click", -2.0))
	elif n is Slider:
		(n as Slider).drag_ended.connect(func(_c: bool) -> void: play_ui("ui_click", -6.0))


func _on_hover(b: BaseButton) -> void:
	if b.disabled:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hover > 60:
		_last_hover = now
		play_ui("ui_hover", -8.0)
