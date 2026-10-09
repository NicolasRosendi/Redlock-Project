class_name SkillDB
extends RefCounted
## Datos de técnicas especiales (paleta R2) y tipos de Despertar.
## Pensado para crecer: en el modo carrera el jugador desbloqueará técnicas y
## las equipará en las ranuras, como las súper/definitivas de Xenoverse 2.

const BAR := 100.0
const MAX_BARS := 5
const MAX_ENERGY := BAR * MAX_BARS
const AWAKEN_DURATION := 20.0

## Ganancia de energía por acción.
const GAIN := {
	"pass": 10.0, "through": 16.0, "shot_on_target": 18.0, "goal": 60.0, "assist": 25.0,
	"tackle": 25.0, "interception": 25.0, "dribble": 20.0, "feint": 5.0, "save": 30.0,
	"block": 15.0, "header": 8.0, "touch": 2.0,
}

const SPECIALS := {
	"pase_meteoro": {
		"name": "PASE METEORO", "kind": "pass", "bars": 1, "color": Color(0.3, 0.95, 1.0),
		"desc": "Pase rasante a gran velocidad que los rivales no pueden interceptar.",
	},
	"quite_relampago": {
		"name": "QUITE RELÁMPAGO", "kind": "tackle", "bars": 1, "color": Color(1.0, 0.88, 0.2),
		"desc": "Embestida veloz que roba el balón o lo intercepta a distancia.",
	},
	"regate_fantasma": {
		"name": "REGATE FANTASMA", "kind": "dribble", "bars": 1, "color": Color(0.75, 0.45, 1.0),
		"desc": "Aceleración intocable con el balón; desequilibra a los rivales cercanos.",
	},
	"disparo_directo": {
		"name": "DISPARO DIRECTO", "kind": "shot", "bars": 2, "color": Color(1.0, 0.42, 0.15),
		"break": 0.35, "desc": "Disparo instantáneo y muy potente que supera al portero.",
	},
	"meteoro_descendente": {
		"name": "METEORO DESCENDENTE", "kind": "shot", "bars": 3, "color": Color(1.0, 0.2, 0.55),
		"break": 0.55, "desc": "Sube, gira y cae en picada a la escuadra. Casi imposible de atajar.",
	},
	"despertar": {
		"name": "DESPERTAR", "kind": "awaken", "bars": 3, "color": Color(0.25, 0.65, 1.0),
		"desc": "Entra en estado de Flow según tu tipo de despertar durante 20 s.",
	},
}

const AWAKENINGS := [
	{"id": "tiro", "name": "Ego Cañonero", "color": Color(1.0, 0.35, 0.2),
		"desc": "Disparos mucho más potentes y precisos."},
	{"id": "fisico", "name": "Cuerpo de Acero", "color": Color(0.95, 0.75, 0.2),
		"desc": "Más fuerza en los choques y resistencia casi infinita."},
	{"id": "salto", "name": "Alas de Cóndor", "color": Color(0.4, 1.0, 0.5),
		"desc": "Saltos enormes: cabezazos y voleas de lujo."},
	{"id": "velocidad", "name": "Velocidad Divina", "color": Color(0.3, 0.9, 1.0),
		"desc": "Velocidad punta y aceleración extremas."},
	{"id": "prediccion", "name": "Metavisión Predictiva", "color": Color(0.8, 0.4, 1.0),
		"desc": "Ves dónde caerá el balón; seguir la ruta marcada te acelera."},
	{"id": "vision", "name": "Visión Espacial", "color": Color(0.2, 0.6, 1.0),
		"desc": "Radar con el balón y las intenciones rivales; pases difíciles de cortar."},
]

const SKILL_MOVE_NAMES := {
	"toque_largo": "Toque largo", "recorte": "Recorte", "arrastre": "Arrastre",
	"sombrero": "¡Sombrero!", "elastico": "¡Elástica!", "ruleta": "¡Ruleta!",
}


static func special(id: String) -> Dictionary:
	return SPECIALS.get(id, {})


static func awakening(idx: int) -> Dictionary:
	return AWAKENINGS[posmod(idx, AWAKENINGS.size())]


static func awakening_by_id(id: String) -> Dictionary:
	for a in AWAKENINGS:
		if a["id"] == id:
			return a
	return AWAKENINGS[0]
