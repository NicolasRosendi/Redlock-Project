extends Node
## Configuración global de la partida. Se rellena desde el menú principal.

enum ControlMode { PRO, TEAM, AI_ONLY }

const TEAM_SIZES := [3, 5, 7, 11]
const DURATIONS := [3.0, 5.0, 8.0, 12.0]
const DIFFICULTIES := ["Fácil", "Normal", "Difícil"]
const CONTROL_NAMES := ["Pro (solo tu jugador)", "Equipo (cambio automático)", "Espectador (IA vs IA)"]
const CAMERA_NAMES := ["Transmisión", "Detrás del jugador"]

var control_mode: int = ControlMode.PRO
var team_size := 7
var match_minutes := 5.0
var difficulty := 1
var awakening := 0
var camera_mode := 0

## Perfil del jugador creado. Es la semilla de la futura personalización
## estilo Xenoverse 2 (apariencia, atributos, técnicas equipadas).
## Nombres de los atributos para la ficha del jugador.
const STAT_NAMES := {
	"shot_acc": "Tiro", "shot_power": "Potencia", "curve": "Curva", "passing": "Pase",
	"dribble": "Regate", "speed": "Velocidad", "accel": "Aceleración", "strength": "Fuerza",
	"tackle": "Quite", "intercept": "Anticipación", "jump": "Salto", "reflex": "Reflejos",
}

var profile := {
	"name": "TÚ",
	"number": 11,
	"skin": Color(0.93, 0.76, 0.6),
	"hair": Color(0.08, 0.08, 0.1),
	"stats": {
		"speed": 0.72, "accel": 0.72, "shot_power": 0.75, "shot_acc": 0.72, "curve": 0.7,
		"passing": 0.66, "dribble": 0.72, "tackle": 0.5, "strength": 0.6,
		"jump": 0.6, "intercept": 0.55, "reflex": 0.3,
	},
	# Kit de técnicas equipadas en la paleta R2 (y R2 + L2). Vacío = ranura libre.
	# Se edita en el menú "Kit de habilidades".
	"palette": SkillDB.DEFAULT_PALETTE.duplicate(),
	"palette_l2": SkillDB.DEFAULT_PALETTE_L2.duplicate(),
}
