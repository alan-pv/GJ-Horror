extends Node

## Autoload "UiSounds": hover and click sound plus a nudge of movement on every
## button in the project, found as it enters the tree. No scene wires anything.

const HOVER_SCALE := 1.06
const HOVER_TIME := 0.12

## The tilt is measured against a button of this size, in pixels, and scaled
## from there: the same few degrees read as a twitch on a small button and as a
## lurch on a wide one.
const ROT_REF_SIZE := 160.0
const ROT_BASE := 2.5
const ROT_MIN := 0.6
const ROT_MAX := 6.0

## Lifted while hovered, so a button that grows is not clipped by its neighbours.
const HOVER_Z_INDEX := 100

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_scan(get_tree().root)

func _scan(node: Node) -> void:
	if node is BaseButton:
		_setup(node)
	for child in node.get_children():
		_scan(child)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_setup(node)

func _setup(btn: BaseButton) -> void:
	if btn.has_meta("btnfx"):
		return
	btn.set_meta("btnfx", true)
	btn.mouse_entered.connect(_on_hover.bind(btn))
	btn.mouse_exited.connect(_on_unhover.bind(btn))
	btn.pressed.connect(_on_click.bind(btn))

func _fx_target(btn: Control) -> Control:
	var p := btn.get_parent()
	if p is Control and p.name == "Anim":
		return p
	return btn

## Remembers the button's own z_index the first time it is lifted, so putting
## it back does not flatten a button the scene deliberately raised.
func _raise_z(c: Control) -> void:
	if not c.has_meta("btnfx_z_original"):
		c.set_meta("btnfx_z_original", c.z_index)
	c.z_index = HOVER_Z_INDEX

func _restore_z(c: Control) -> void:
	if c.has_meta("btnfx_z_original"):
		c.z_index = c.get_meta("btnfx_z_original")

## What a button settles back to once a bump is over: still grown while the
## pointer is on it, its own size once it has left.
func _rest_scale(c: Control) -> Vector2:
	return Vector2.ONE * HOVER_SCALE if c.get_meta("btnfx_hover", false) else Vector2.ONE

func _rot_amount(c: Control) -> float:
	var s: float = maxf(maxf(c.size.x, c.size.y), 1.0)
	return clampf(ROT_BASE * ROT_REF_SIZE / s, ROT_MIN, ROT_MAX)

func _kill(c: Control, key: String) -> void:
	if not c.has_meta(key):
		return
	var old: Variant = c.get_meta(key)
	if old is Tween and old.is_valid():
		old.kill()

func _on_hover(btn: BaseButton) -> void:
	if btn.disabled:
		return
	var c := _fx_target(btn)
	c.set_meta("btnfx_hover", true)
	_raise_z(c)
	AudioManager.play_sfx(AudioManager.SFX_HOVER)
	_bump(btn)

func _on_unhover(btn: BaseButton) -> void:
	var c := _fx_target(btn)
	c.set_meta("btnfx_hover", false)
	_restore_z(c)
	if c.is_in_group("ui_intro_playing"):
		return
	_kill(c, "bump_scale")
	c.pivot_offset = c.size * 0.5
	var sc := c.create_tween()
	sc.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sc.tween_property(c, "scale", Vector2.ONE, HOVER_TIME)
	c.set_meta("bump_scale", sc)

func _on_click(btn: BaseButton) -> void:
	AudioManager.play_sfx(AudioManager.SFX_CLICK)
	_bump(btn)

func _bump(btn: BaseButton) -> void:
	var c := _fx_target(btn)
	if c.is_in_group("ui_intro_playing"):
		return
	c.pivot_offset = c.size * 0.5
	_kill(c, "bump_scale")
	_kill(c, "bump_rot")
	var dir: float = [-1.0, 1.0].pick_random()
	var deg := _rot_amount(c)
	var rot := c.create_tween()
	rot.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	rot.tween_property(c, "rotation_degrees", deg * dir, 0.1)
	rot.tween_property(c, "rotation_degrees", 0.0, 0.7)
	c.set_meta("bump_rot", rot)
	var rest := _rest_scale(c)
	var sc := c.create_tween()
	sc.tween_property(c, "scale", rest * Vector2(0.80, 1.1), 0.1)
	sc.tween_property(c, "scale", rest, 0.1)
	c.set_meta("bump_scale", sc)
