extends Node
## Autoload. Animates the UI of every scene into view.
## Registered in Project Settings > Autoload as "UiIntro".

@export var duration := 0.35
@export var stagger := 0.05
@export var max_total_delay := 3.0
@export var typewriter := true
@export var typewriter_speed := 0.025

var _pending: Array[Control] = []


func _ready() -> void:
	# The first scene never goes through the switcher, so catch it here.
	_boot.call_deferred()


func _boot() -> void:
	await get_tree().process_frame
	var root := get_tree().current_scene
	if root:
		prepare(root)
		play()


# ------------------------------------------------ public API

## Hides the UI. Call it while the screen is still covered by the fade.
func prepare(root: Node) -> void:
	_pending.clear()
	# Solo animan las pantallas de interfaz; la escena 3D de la partida no se toca.
	if root != null and not root is Control:
		return
	if root == null or not is_instance_valid(root):
		push_warning("UiIntro.prepare(): null root, skipping the intro.")
		return
	_collect_into(root, _pending, _cfg(root))
	for c in _pending:
		_hide(c)


## Plays whatever prepare() collected.
func play() -> void:
	await get_tree().process_frame   # containers lay out on this frame
	_run(_pending)
	_pending.clear()


## For nodes created at runtime.
func intro_for(what: Variant) -> void:
	var list: Array[Control] = []
	if what is Array:
		for n in what:
			if n is Control:
				list.append(n)
	elif what is Control:
		list.append(what)
	elif what is Node:
		_collect_into(what, list, {})

	for c in list:
		_hide(c)
	await get_tree().process_frame
	_run(list)


# ------------------------------------------------ internals

## Optional per-scene config: define _intro_config() on the root script.
func _cfg(root: Node) -> Dictionary:
	if root == null:
		return {}
	if root.has_method("_intro_config"):
		return root._intro_config()
	return {}


func _collect_into(node: Node, out: Array[Control], cfg: Dictionary) -> void:
	for child in node.get_children():
		if child.is_in_group("no_intro"):
			continue
		if child.is_in_group("intro_as_group") and child is Control:
			out.append(child)
			continue
		if child is Control and _matches(child, cfg):
			out.append(child)
		else:
			_collect_into(child, out, cfg)


func _matches(c: Control, cfg: Dictionary) -> bool:
	if c is BaseButton:
		return cfg.get("buttons", true)
	if c is Label or c is RichTextLabel:
		return cfg.get("labels", true)
	if c is Panel or c is PanelContainer:
		return cfg.get("panels", false)
	return false


func _is_scalable(c: Control) -> bool:
	return c is BaseButton or c is Panel or c is PanelContainer


func _hide(c: Control) -> void:
	c.modulate.a = 0.0
	if typewriter and (c is Label or c is RichTextLabel):
		c.visible_ratio = 0.0


func _run(list: Array[Control]) -> void:
	# Spread the delay rather than truncating it: with many nodes the step
	# shrinks so the last one still lands inside max_total_delay.
	var step := stagger
	if list.size() > 1:
		step = minf(stagger, max_total_delay / float(list.size() - 1))

	var i := 0
	for c in list:
		if not is_instance_valid(c) or not c.is_inside_tree():
			continue
		if _is_scalable(c):
			c.scale = Vector2.ZERO
			c.modulate.a = 1.0
		_animate(c, i * step)
		i += 1


func _animate(c: Control, delay: float) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.set_parallel(true)

	if _is_scalable(c):
		tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "scale", Vector2.ONE, duration).set_delay(delay)
	else:
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate:a", 1.0, duration * 0.6).set_delay(delay)
		if typewriter and (c is Label or c is RichTextLabel):
			tw.tween_property(c, "visible_ratio", 1.0, c.text.length() * typewriter_speed) \
				.set_delay(delay).set_trans(Tween.TRANS_LINEAR)
