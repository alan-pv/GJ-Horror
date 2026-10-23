class_name DialogueText
extends RefCounted
## Utilidades puras (sin nodos) para los textos de diálogo del HUD: quitar el bbcode para obtener el
## texto plano (el que balbucea `VoiceBlips`), dividir un texto largo en trozos que caben en dos filas
## y calcular cuándo aparece cada letra para que la máquina de escribir siga los blips de la voz.
##
## El bbcode que entiende es el de `RichTextLabel`: etiquetas en minúsculas como `[wave]`,
## `[shake rate=20]`, `[/wave]`. Un corchete literal se escribe `[lb]` / `[rb]`.

## Ritmo (s por carácter) del texto que sobrepasa el tope del balbuceo.
const TAIL_RATE := 0.045
## Etiqueta bbcode: `[nombre]`, `[nombre=valor]`, `[nombre a=1 b=2]` o `[/nombre]`.
const TAG_PATTERN := "^\\[(/?)([a-z_]+)(?:[= ][^\\]]*)?\\]"

static var _tag_re: RegEx = null


## Descompone `markup` en átomos: `{src, vis, kind}`. `kind` = "char" (un carácter visible; `vis` es
## lo que se ve y `src` cómo se escribió, p. ej. `[lb]` -> `[`), "open" (etiqueta de apertura, con
## `name`) o "close" (etiqueta de cierre, con `name`).
static func atoms(markup: String) -> Array[Dictionary]:
	if _tag_re == null:
		_tag_re = RegEx.create_from_string(TAG_PATTERN)
	var out: Array[Dictionary] = []
	var i := 0
	while i < markup.length():
		var c := markup[i]
		if c == "[":
			var m := _tag_re.search(markup.substr(i))
			if m != null:
				var tag := m.get_string()
				var tag_name := m.get_string(2)
				if m.get_string(1) == "" and tag_name == "lb":
					out.append({"src": tag, "vis": "[", "kind": "char"})
				elif m.get_string(1) == "" and tag_name == "rb":
					out.append({"src": tag, "vis": "]", "kind": "char"})
				elif m.get_string(1) == "/":
					out.append({"src": tag, "vis": "", "kind": "close", "name": tag_name})
				else:
					out.append({"src": tag, "vis": "", "kind": "open", "name": tag_name})
				i += tag.length()
				continue
		out.append({"src": c, "vis": c, "kind": "char"})
		i += 1
	return out


## Texto que se ve (lo que cuenta `visible_characters` y lo que dice la voz): `markup` sin etiquetas.
static func plain(markup: String) -> String:
	var s := ""
	for a in atoms(markup):
		s += a.vis
	return s


## ¿Es letra o cifra (la que suena en `VoiceBlips.plan`)?
static func is_alnum(ch: String) -> bool:
	if ch == "":
		return false
	var c := ch.unicode_at(0)
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c >= 192


## Instante (s) en que se hace visible cada carácter de `text` (texto plano), alineado con `plan`
## (`VoiceBlips.plan`): la letra n-ésima aparece cuando suena su blip n-ésimo; espacios y puntuación
## aparecen con la letra anterior (los iniciales, en 0). Lo que sobrepasa el tope del balbuceo
## aparece a `TAIL_RATE` s por carácter.
static func reveal_times(plan: Array, text: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(text.length())
	var k := 0
	var last := 0.0
	var beyond := false
	for i in text.length():
		var ch := text[i]
		if is_alnum(ch):
			if k < plan.size():
				last = float(plan[k].t)
			else:
				beyond = true
			k += 1
		if beyond:
			last += TAIL_RATE
		out[i] = last
	return out


## Cuántos caracteres son visibles en el instante `t` (`times` de `reveal_times`, no decreciente).
static func reveal_count(times: PackedFloat32Array, t: float) -> int:
	var n := 0
	while n < times.size() and times[n] <= t:
		n += 1
	return n


## Segundos que tarda en escribirse `text` (plano) con la voz `speaker`.
static func typing_seconds(speaker: VoiceBlips.Speaker, text: String) -> float:
	var plan := VoiceBlips.plan(speaker, text)
	var times := reveal_times(plan, text)
	var t := VoiceBlips.duration(speaker, text)
	if times.size() > 0:
		t = maxf(t, times[times.size() - 1] + 0.05)
	return t


## Divide `markup` en trozos que `fits` (Callable: texto plano -> bool) acepta. Primero por frases
## (agrupa cuantas quepan), y si una frase sola no cabe, por palabras. Cada trozo conserva el
## bbcode equilibrado (cierra al final lo que estuviera abierto y lo reabre en el trozo siguiente).
## Una palabra que no cabe sola va en su propio trozo. Si todo cabe, devuelve `[markup]`.
static func split(markup: String, fits: Callable) -> Array[String]:
	var at := atoms(markup)
	var vis: Array[int] = []   # índice del átomo de cada carácter visible
	var text := ""
	for i in at.size():
		if at[i].kind == "char":
			vis.append(i)
			text += at[i].vis
	if text.strip_edges() == "" or bool(fits.call(text)):
		return [markup]
	var n := text.length()
	var sentence_ends: Array[int] = []
	var word_ends: Array[int] = []
	for i in n:
		var c := text[i]
		var next := text[i + 1] if i + 1 < n else " "
		if c not in [" ", "\n"] and next in [" ", "\n"]:
			word_ends.append(i + 1)
			if c in [".", "!", "?", "…"]:
				sentence_ends.append(i + 1)
	var chunks: Array[String] = []
	var start := 0
	while start < n:
		while start < n and text[start] in [" ", "\n"]:
			start += 1
		if start >= n:
			break
		var end := _best_end(text, start, sentence_ends, fits)
		if end <= start:
			end = _best_end(text, start, word_ends, fits)
		if end <= start:
			# Ni una palabra cabe: la primera palabra sola.
			end = n
			for e in word_ends:
				if e > start:
					end = e
					break
		chunks.append(_render(at, vis, start, end))
		start = end
	return chunks


## Mayor fin de `ends` (> `start`) tal que `text[start:end]` cabe; 0 si ninguno.
static func _best_end(text: String, start: int, ends: Array[int], fits: Callable) -> int:
	var best := 0
	for e in ends:
		if e <= start:
			continue
		if bool(fits.call(text.substr(start, e - start))):
			best = e
		else:
			break
	return best


## Markup del rango de caracteres visibles [a, b) con las etiquetas equilibradas.
static func _render(at: Array[Dictionary], vis: Array[int], a: int, b: int) -> String:
	var first_atom: int = vis[a]
	var last_atom: int = vis[b - 1]
	var stack: Array[Dictionary] = []
	var out := ""
	for i in at.size():
		var atom := at[i]
		if i == first_atom:
			for o in stack:
				out += o.src
		if atom.kind == "open":
			stack.append(atom)
		elif atom.kind == "close":
			for k in range(stack.size() - 1, -1, -1):
				if stack[k].name == atom.name:
					stack.remove_at(k)
					break
		if i < first_atom:
			continue
		if i > last_atom:
			break
		if atom.kind == "char" or (i > first_atom):
			out += atom.src
	for k in range(stack.size() - 1, -1, -1):
		out += "[/%s]" % stack[k].name
	return out
