class_name HudWidgets
extends RefCounted
## Controles dibujados a mano para el HUD (sin depender de glifos de fuente
## para los símbolos de PlayStation).


static func draw_button_icon(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color) -> void:
	match kind:
		"cross":
			ci.draw_line(c + Vector2(-r, -r) * 0.6, c + Vector2(r, r) * 0.6, col, 3.0, true)
			ci.draw_line(c + Vector2(-r, r) * 0.6, c + Vector2(r, -r) * 0.6, col, 3.0, true)
		"circle":
			ci.draw_arc(c, r * 0.62, 0.0, TAU, 24, col, 3.0, true)
		"triangle":
			var pts := PackedVector2Array([c + Vector2(0, -r * 0.7), c + Vector2(r * 0.65, r * 0.5), c + Vector2(-r * 0.65, r * 0.5), c + Vector2(0, -r * 0.7)])
			ci.draw_polyline(pts, col, 3.0, true)
		"square":
			ci.draw_rect(Rect2(c - Vector2(r, r) * 0.55, Vector2(r, r) * 1.1), col, false, 3.0)


## Panel inferior izquierdo: nombre, estamina (con tope por fatiga) y energía.
class Bars:
	extends Control
	var m: Match
	var flash := 0.0

	func _process(delta: float) -> void:
		flash = maxf(flash - delta * 2.0, 0.0)
		queue_redraw()

	func _draw() -> void:
		if m == null or m.human == null or m.human.player == null:
			return
		var p: Player = m.human.player
		var font := ThemeDB.fallback_font
		var w := size.x
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.1, 0.72))
		draw_rect(Rect2(Vector2.ZERO, Vector2(6, size.y)), p.team.color)
		var a := SkillDB.awakening_by_id(p.awakening_id)
		draw_string(font, Vector2(16, 26), "%s  #%d" % [p.player_name, p.number], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		var aw_text := "Despertar: %s" % a["name"]
		if p.awakened:
			aw_text = "¡%s! %.0fs" % [a["name"], p.awaken_left]
		draw_string(font, Vector2(16, 46), aw_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, a["color"] if p.awakened else Color(0.75, 0.8, 0.9))
		# Estamina
		var bx := 16.0
		var bw := w - 32.0
		var y := 58.0
		draw_string(font, Vector2(bx, y + 12), "ESTAMINA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.85, 0.75))
		y += 18.0
		draw_rect(Rect2(bx, y, bw, 12), Color(0.1, 0.1, 0.12))
		var cap_x := bx + bw * p.stamina_cap / 100.0
		draw_rect(Rect2(cap_x, y, bx + bw - cap_x, 12), Color(0.35, 0.08, 0.08))
		var s := p.stamina / 100.0
		var sc := Color(0.3, 0.9, 0.4).lerp(Color(0.95, 0.85, 0.2), clampf(1.0 - s * 1.6, 0.0, 1.0))
		if s < 0.15:
			sc = Color(0.95, 0.25, 0.2)
		draw_rect(Rect2(bx, y, bw * s, 12), sc)
		draw_line(Vector2(cap_x, y - 2), Vector2(cap_x, y + 14), Color(1, 1, 1, 0.8), 2.0)
		# Energía (barras estilo Ki)
		y += 22.0
		draw_string(font, Vector2(bx, y + 12), "ENERGÍA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.85, 1.0))
		y += 18.0
		var gap := 4.0
		var seg := (bw - gap * (SkillDB.MAX_BARS - 1)) / SkillDB.MAX_BARS
		for i in SkillDB.MAX_BARS:
			var x := bx + i * (seg + gap)
			draw_rect(Rect2(x, y, seg, 14), Color(0.08, 0.1, 0.16))
			var fill := clampf((p.energy - i * SkillDB.BAR) / SkillDB.BAR, 0.0, 1.0)
			var col := Color(0.25, 0.75, 1.0) if fill < 1.0 else Color(0.45, 0.95, 1.0)
			if fill >= 1.0 and flash > 0.0:
				col = col.lerp(Color.WHITE, flash)
			draw_rect(Rect2(x, y, seg * fill, 14), col)
			if fill >= 1.0:
				draw_rect(Rect2(x, y, seg, 14), Color(1, 1, 1, 0.5), false, 1.5)
		draw_string(font, Vector2(bx + bw - 30, y - 4), "%d" % int(p.energy / SkillDB.BAR), HORIZONTAL_ALIGNMENT_RIGHT, 30, 14, Color(0.6, 0.9, 1.0))


## Paleta de técnicas (R2), estilo Xenoverse: rombo con las 4 ranuras.
class Palette:
	extends Control
	var m: Match

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if m == null or m.human == null or m.human.player == null:
			return
		var p: Player = m.human.player
		var font := ThemeDB.fallback_font
		var r2 := Input.is_action_pressed("power")
		var l2 := Input.is_action_pressed("mark")
		var center := size * 0.5
		if not r2:
			draw_string(font, Vector2(0, size.y - 8), "R2: técnicas   R2+L2: técnicas alternas", HORIZONTAL_ALIGNMENT_RIGHT, size.x, 14, Color(1, 1, 1, 0.55))
			return
		var pal: Dictionary = m.human.palette_for(l2)
		var slots := {"triangle": Vector2(0, -70), "circle": Vector2(110, 0), "cross": Vector2(0, 70), "square": Vector2(-110, 0)}
		draw_circle(center, 120.0, Color(0.02, 0.04, 0.1, 0.55))
		draw_string(font, center + Vector2(-60, -112), "R2 + L2" if l2 else "R2", HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color(1, 0.9, 0.5))
		for k in slots:
			var c: Vector2 = center + slots[k]
			var sid: String = pal.get(k, "")
			var sd := SkillDB.special(sid)
			var ok := not sd.is_empty() and p.energy >= float(sd["bars"]) * SkillDB.BAR
			var col: Color = sd.get("color", Color(0.5, 0.5, 0.5))
			if not ok:
				col = col.darkened(0.55)
			draw_circle(c, 26.0, Color(0.05, 0.07, 0.14, 0.95))
			draw_arc(c, 26.0, 0.0, TAU, 32, col, 3.0, true)
			HudWidgets.draw_button_icon(self, k, c, 16.0, Color.WHITE if ok else Color(0.6, 0.6, 0.6))
			var label := "(libre)" if sd.is_empty() else String(sd["name"])
			var bars := 0 if sd.is_empty() else int(sd["bars"])
			var cost := "" if bars == 0 else ("1 barra" if bars == 1 else "%d barras" % bars)
			draw_string(font, c + Vector2(-80, 44), label, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, col.lightened(0.3))
			draw_string(font, c + Vector2(-80, 60), cost, HORIZONTAL_ALIGNMENT_CENTER, 160, 12, Color(0.6, 0.9, 1.0) if ok else Color(0.5, 0.5, 0.55))


## Radar de Visión Espacial: balón, jugadores e intenciones de los rivales.
class Radar:
	extends Control
	var m: Match

	func _process(_delta: float) -> void:
		visible = m != null and m.human != null and m.human.player != null and m.human.player.is_awakened_as("vision")
		if visible:
			queue_redraw()

	func _to_map(p: Vector3) -> Vector2:
		var sx := size.x / (m.hl * 2.0 + 4.0)
		var sy := size.y / (m.hw * 2.0 + 4.0)
		return Vector2((p.x + m.hl + 2.0) * sx, (p.z + m.hw + 2.0) * sy)

	func _draw() -> void:
		if m == null or m.human == null or m.human.player == null:
			return
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.1, 0.2, 0.75))
		var tl := _to_map(Vector3(-m.hl, 0, -m.hw))
		var br := _to_map(Vector3(m.hl, 0, m.hw))
		draw_rect(Rect2(tl, br - tl), Color(0.4, 0.8, 1.0, 0.6), false, 1.5)
		draw_line(_to_map(Vector3(0, 0, -m.hw)), _to_map(Vector3(0, 0, m.hw)), Color(0.4, 0.8, 1.0, 0.4), 1.0)
		var me: Player = m.human.player
		for t in m.teams:
			for p in t.players:
				var c := _to_map(p.position)
				var col := t.color.lightened(0.3)
				draw_circle(c, 4.5 if p != me else 6.0, col)
				if p == me:
					draw_arc(c, 9.0, 0.0, TAU, 20, Color(1, 0.85, 0.1), 2.0)
				if t != me.team and p.brain != null and not p.brain.intent.is_empty():
					var it: Dictionary = p.brain.intent
					var to := _to_map(it["pos"])
					match it["type"]:
						"pass":
							draw_dashed_line(c, to, Color(1.0, 0.4, 0.3, 0.9), 2.0, 6.0)
						"shot":
							draw_line(c, to, Color(1.0, 0.15, 0.15), 3.0)
							draw_string(font, c + Vector2(6, -6), "¡TIRO!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.3, 0.3))
						"run":
							draw_dashed_line(c, to, Color(1.0, 0.75, 0.3, 0.7), 1.5, 4.0)
						"press":
							draw_line(c, c.lerp(to, 0.6), Color(1.0, 0.6, 0.2, 0.7), 1.5)
		# Balón y su trayectoria
		var bp := _to_map(m.ball.position)
		var prev := bp
		var i := 0
		for pt in m.ball_path:
			i += 1
			if i % 4 != 0:
				continue
			var q := _to_map(pt)
			draw_line(prev, q, Color(1, 1, 1, 0.45), 1.0)
			prev = q
		draw_circle(bp, 4.0, Color.WHITE)
		draw_string(font, Vector2(6, 16), "VISIÓN ESPACIAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.85, 1.0))


## Barra de potencia sobre la cabeza del jugador mientras carga.
class Charge:
	extends Control
	var m: Match

	func _process(_delta: float) -> void:
		var p: Player = m.human.player if m != null and m.human != null else null
		visible = p != null and p.charge_kind != "" and not m.cam.is_position_behind(p.position + Vector3.UP * 2.3)
		if visible:
			position = m.cam.unproject_position(p.position + Vector3.UP * 2.6) - Vector2(size.x * 0.5, 0)
			queue_redraw()

	func _draw() -> void:
		if m == null or m.human == null or m.human.player == null:
			return
		var p: Player = m.human.player
		var c := p.charge_amount()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7))
		var col := Color(0.3, 0.9, 1.0) if p.charge_kind != "shot" and p.charge_kind != "chip" else Color(1.0, 0.75, 0.2)
		if c > 0.85 and (p.charge_kind == "shot" or p.charge_kind == "chip"):
			col = Color(1.0, 0.25, 0.2)
		draw_rect(Rect2(2, 2, (size.x - 4) * c, size.y - 4), col)
		draw_line(Vector2(size.x * 0.85, 0), Vector2(size.x * 0.85, size.y), Color(1, 1, 1, 0.6), 1.0)
