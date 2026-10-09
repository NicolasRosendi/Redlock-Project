class_name SkillDB
extends RefCounted
## Datos de técnicas especiales (paleta R2) y tipos de Despertar.
## El jugador arma su kit antes del partido (8 ranuras, como las súper y
## definitivas de Xenoverse 2): puede llevar, por ejemplo, dos tiros distintos.

const BAR := 100.0
const MAX_BARS := 5
const MAX_ENERGY := BAR * MAX_BARS
const AWAKEN_DURATION := 20.0

## Ganancia de energía por acción.
const GAIN := {
	"pass": 10.0, "through": 16.0, "shot_on_target": 18.0, "goal": 60.0, "assist": 25.0,
	"tackle": 25.0, "interception": 25.0, "dribble": 20.0, "feint": 5.0, "save": 30.0,
	"block": 15.0, "header": 8.0, "touch": 2.0, "poke": 18.0,
}

const KIND_NAMES := {"pass": "Pase", "shot": "Tiro", "dribble": "Regate", "tackle": "Defensa", "awaken": "Transformación"}

const SPECIALS := {
	# --- Tiros
	"disparo_directo": {
		"name": "DISPARO DIRECTO", "kind": "shot", "bars": 2, "color": Color(1.0, 0.42, 0.15), "break": 0.35,
		"desc": "Disparo recto, instantáneo y muy potente que supera al portero.",
	},
	"curva_del_ego": {
		"name": "CURVA DEL EGO", "kind": "shot", "bars": 2, "color": Color(0.3, 1.0, 0.5), "break": 0.4,
		"desc": "Sale por fuera del arco y se cierra con una curva enorme hacia la escuadra.",
	},
	"tiro_fantasma": {
		"name": "TIRO FANTASMA", "kind": "shot", "bars": 2, "color": Color(0.85, 0.85, 1.0), "break": 0.45,
		"desc": "Tiro sin rotación que baila en el aire y engaña al portero.",
	},
	"meteoro_descendente": {
		"name": "METEORO DESCENDENTE", "kind": "shot", "bars": 3, "color": Color(1.0, 0.2, 0.55), "break": 0.55,
		"desc": "Sube, gira y cae en picada a la escuadra. Casi imposible de atajar.",
	},
	# --- Regates
	"regate_fantasma": {
		"name": "REGATE FANTASMA", "kind": "dribble", "bars": 1, "color": Color(0.75, 0.45, 1.0),
		"desc": "1,3 s intocable y más rápido con el balón; los rivales que cruzas caen.",
	},
	"regate_relampago": {
		"name": "REGATE RELÁMPAGO", "kind": "dribble", "bars": 1, "color": Color(1.0, 1.0, 0.4),
		"desc": "Zigzag instantáneo hacia donde apunta el stick; deja clavado al rival.",
	},
	"sombrero_celestial": {
		"name": "SOMBRERO CELESTIAL", "kind": "dribble", "bars": 2, "color": Color(0.55, 0.9, 1.0),
		"desc": "Levanta el balón por encima del rival y lo recoges al otro lado.",
	},
	"torbellino": {
		"name": "TORBELLINO", "kind": "dribble", "bars": 1, "color": Color(0.3, 0.95, 0.85),
		"desc": "Ruleta explosiva que derriba a los rivales que tienes encima.",
	},
	# --- Pases
	"pase_meteoro": {
		"name": "PASE METEORO", "kind": "pass", "bars": 1, "color": Color(0.3, 0.95, 1.0),
		"desc": "Pase rasante a gran velocidad que los rivales no pueden interceptar.",
	},
	"pase_bumeran": {
		"name": "PASE BUMERÁN", "kind": "pass", "bars": 1, "color": Color(0.5, 1.0, 0.6),
		"desc": "Pase con una curva imposible que rodea a la defensa; no se puede cortar.",
	},
	"centro_teledirigido": {
		"name": "CENTRO TELEDIRIGIDO", "kind": "pass", "bars": 1, "color": Color(1.0, 0.92, 0.45),
		"desc": "Centro perfecto a la cabeza del compañero, que remata de primera.",
	},
	# --- Defensa
	"quite_relampago": {
		"name": "QUITE RELÁMPAGO", "kind": "tackle", "bars": 1, "color": Color(1.0, 0.88, 0.2),
		"desc": "Embestida veloz que roba el balón o lo intercepta a distancia.",
	},
	"muro_de_acero": {
		"name": "MURO DE ACERO", "kind": "tackle", "bars": 1, "color": Color(0.7, 0.82, 1.0),
		"desc": "Durante 3 s bloqueas cualquier pase o tiro que pase a tu alrededor.",
	},
	# --- Transformación
	"despertar": {
		"name": "DESPERTAR", "kind": "awaken", "bars": 3, "color": Color(0.25, 0.65, 1.0),
		"desc": "Entra en estado de Flow según tu tipo de despertar durante 20 s.",
	},
}

## Orden en que se recorren las técnicas en el editor de kit ("" = ranura vacía).
const KIT_ORDER := [
	"", "disparo_directo", "curva_del_ego", "tiro_fantasma", "meteoro_descendente",
	"regate_fantasma", "regate_relampago", "sombrero_celestial", "torbellino",
	"pase_meteoro", "pase_bumeran", "centro_teledirigido",
	"quite_relampago", "muro_de_acero", "despertar",
]

const DEFAULT_PALETTE := {"cross": "pase_meteoro", "circle": "quite_relampago", "triangle": "regate_fantasma", "square": "disparo_directo"}
const DEFAULT_PALETTE_L2 := {"cross": "centro_teledirigido", "circle": "despertar", "triangle": "regate_relampago", "square": "curva_del_ego"}

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
