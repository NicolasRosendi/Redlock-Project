extends Node
## Registra todas las acciones de entrada por código (mando primero, teclado
## como respaldo). Distribución pensada para mando de PlayStation; en Xbox:
## Cruz=A, Círculo=B, Cuadrado=X, Triángulo=Y, L1/R1=LB/RB, L2/R2=LT/RT.

const STICK_DEADZONE := 0.22
const TRIGGER_DEADZONE := 0.35


func _ready() -> void:
	# Movimiento (stick izquierdo / WASD)
	_add("move_left", [_axis(JOY_AXIS_LEFT_X, -1.0), _key(KEY_A)])
	_add("move_right", [_axis(JOY_AXIS_LEFT_X, 1.0), _key(KEY_D)])
	_add("move_up", [_axis(JOY_AXIS_LEFT_Y, -1.0), _key(KEY_W)])
	_add("move_down", [_axis(JOY_AXIS_LEFT_Y, 1.0), _key(KEY_S)])
	# Regates (stick derecho / flechas)
	_add("dribble_left", [_axis(JOY_AXIS_RIGHT_X, -1.0), _key(KEY_LEFT)])
	_add("dribble_right", [_axis(JOY_AXIS_RIGHT_X, 1.0), _key(KEY_RIGHT)])
	_add("dribble_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0), _key(KEY_UP)])
	_add("dribble_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0), _key(KEY_DOWN)])
	# Gatillos y bumpers
	_add("sprint", [_btn(JOY_BUTTON_RIGHT_SHOULDER), _key(KEY_SHIFT)])             # R1
	_add("press", [_btn(JOY_BUTTON_LEFT_SHOULDER), _key(KEY_E)])                   # L1
	_add("mark", [_axis(JOY_AXIS_TRIGGER_LEFT, 1.0), _key(KEY_Q)], TRIGGER_DEADZONE)   # L2
	_add("power", [_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), _key(KEY_SPACE)], TRIGGER_DEADZONE)  # R2
	# Botones frontales (distribución en rombo J/K/L/I en teclado)
	_add("btn_cross", [_btn(JOY_BUTTON_A), _key(KEY_K)])
	_add("btn_circle", [_btn(JOY_BUTTON_B), _key(KEY_L)])
	_add("btn_square", [_btn(JOY_BUTTON_X), _key(KEY_J)])
	_add("btn_triangle", [_btn(JOY_BUTTON_Y), _key(KEY_I)])
	# Otros
	_add("switch_player", [_btn(JOY_BUTTON_RIGHT_STICK), _key(KEY_R)])           # R3 (clic)
	_add("camera_toggle", [_btn(JOY_BUTTON_BACK), _key(KEY_C)])                  # Select / Share
	_add("pause", [_btn(JOY_BUTTON_START), _key(KEY_ESCAPE), _key(KEY_P)])        # Start / Options
	_add("awaken_prev", [_btn(JOY_BUTTON_DPAD_LEFT), _key(KEY_1)])
	_add("awaken_next", [_btn(JOY_BUTTON_DPAD_RIGHT), _key(KEY_2)])
	_add("debug_energy", [_btn(JOY_BUTTON_DPAD_UP), _key(KEY_3)])
	_add("help", [_btn(JOY_BUTTON_DPAD_DOWN), _key(KEY_H)])
	# Navegación de menús con el stick izquierdo además de la cruceta
	_add("ui_left", [_axis(JOY_AXIS_LEFT_X, -1.0)])
	_add("ui_right", [_axis(JOY_AXIS_LEFT_X, 1.0)])
	_add("ui_up", [_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add("ui_down", [_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add("ui_accept", [_btn(JOY_BUTTON_A)])
	_add("ui_cancel", [_btn(JOY_BUTTON_B)])


func _add(action: StringName, events: Array, deadzone := STICK_DEADZONE) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
	for e in events:
		if not InputMap.action_has_event(action, e):
			InputMap.action_add_event(action, e)


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = -1
	e.axis = axis
	e.axis_value = value
	return e


func _btn(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = button
	return e


func _key(key: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.device = -1
	e.physical_keycode = key
	return e
