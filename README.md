# Redlock Project

Prototipo de **gameplay** para un RPG de fútbol inspirado en *Blue Lock*, *Captain Tsubasa: Rise of New Champions* y el modo carrera de *FIFA*.
La meta de esta primera etapa es pulir el juego en la cancha: **arcade y fluido**, realista en las jugadas normales y espectacular
(cámara lenta, primeros planos, estelas, auras) en las técnicas especiales.

Motor: **Godot 4.3+** (GDScript). Gráficos sencillos generados por código: no hace falta ningún asset externo.

![Técnica especial](docs/img/tecnica.jpg)

## Cómo jugar

1. Instala [Godot 4.3 o superior](https://godotengine.org/download) (versión estándar, no hace falta la de .NET).
2. Abre Godot → *Importar* → elige `project.godot` de esta carpeta.
3. Pulsa **F5**. Conecta un mando (PlayStation, Xbox o genérico) antes o durante el menú.

En el menú eliges modo de control, formato (3v3, 5v5, 7v7 u 11v11), tipo de **Despertar**, dificultad, duración y cámara.

| Modo | Qué controlas |
|---|---|
| **Pro** | Solo a tu delantero creado (estilo Blue Lock / "Be a Pro"). Con Cruz/Triángulo pides el pase. |
| **Equipo** | Todo el equipo; el control salta al que tiene el balón o al mejor defensor. R3 cambia a mano. |
| **Espectador** | IA contra IA. |

## Controles

Pensados para mando de PlayStation (en Xbox: Cruz=A, Círculo=B, Cuadrado=X, Triángulo=Y). Entre corchetes, el teclado.

| Botón | Ataque (con balón) | Defensa (sin balón) |
|---|---|---|
| Stick izq. [WASD] | Moverse | Moverse |
| **R1** [Shift] | Correr (gasta estamina; el balón se te separa más) | Correr |
| **L2** [Q] | Proteger el balón | Marcar / contener (con stick quieto se coloca solo entre el rival y tu arco) |
| **L1** [E] | Modificador "picar": L1+Cuadrado vaselina, L1+Cruz pase bombeado, L1+Triángulo al hueco por arriba | Presionar (va solo hacia el portador) |
| **Cruz** [K] | Pase raso (mantener = más fuerte) | Cargar con el cuerpo |
| **Círculo** [L] | Centro | Quite |
| **Triángulo** [I] | Pase al hueco | — |
| **Cuadrado** [J] | Tiro (mantener = potencia; pasarse de potencia = se va alto) | Barrida |
| Cuadrado ×2 | **Tiro raso** | — |
| Tiro + Cruz rápido | **Amague** (cancela el tiro; esquivas el siguiente quite) | — |
| **Stick der.** [flechas] | Regates: adelante *toque largo*, lado *recorte*, atrás *arrastre* | — |
| **L2 + stick der.** | Regates mejorados: *sombrero*, *elástica*, *ruleta* | — |
| Balón suelto cerca | Cuadrado/Cruz = remate o pase **de primera** (salta solo a cabecear si viene alto) | |

**Paleta de técnicas (mantener R2), estilo Xenoverse 2** — cuestan barras de energía:

| | R2 | R2 + L2 |
|---|---|---|
| **Cruz** | Pase Meteoro (1) — imposible de interceptar | *(ranura libre)* |
| **Círculo** | Quite Relámpago (1) — embestida que roba o intercepta a distancia | **DESPERTAR** (3) |
| **Triángulo** | Regate Fantasma (1) — intocable 1,3 s, tumba rivales | *(ranura libre)* |
| **Cuadrado** | Disparo Directo (2) | Meteoro Descendente (3) |

Otros: cruceta ←/→ [1/2] cambia el tipo de Despertar, cruceta ↑ [3] energía al máximo (*debug*), cruceta ↓ [H] ayuda,
Select [C] cámara (TV / detrás del jugador), Start [Esc] pausa.

## Sistemas implementados

- **Estamina vs. energía.** La *estamina* se gasta al correr, marcar, chocar, saltar y regatear; al dejar de correr se recupera,
  pero **solo hasta un tope que baja con el cansancio** (la línea blanca de la barra). La *energía* (5 barras) se gana jugando:
  pases completados, quites, intercepciones, tiros al arco, regates, atajadas, goles y asistencias.
- **Despertar (transformación)** durante 20 s, seis tipos: *Ego Cañonero* (tiro), *Cuerpo de Acero* (fuerza y resistencia),
  *Alas de Cóndor* (salto, cabezazos y voleas), *Velocidad Divina*, *Metavisión Predictiva* (marca dónde caerá el balón y una ruta;
  seguirla te acelera) y *Visión Espacial* (radar con el balón y las intenciones de los rivales; tus pases son más difíciles de cortar).
- **Física de balón propia**: rebote, rozamiento, resistencia del aire, curva por efecto (Magnus), caída por *topspin* y *knuckle*.
  El efecto es **automático**: apuntas con el stick y el juego calcula la curva para que el balón llegue donde apuntaste.
- **Porteros** que predicen la trayectoria, se lanzan, atrapan o despejan (los rechazos quedan vivos para remates).
- **IA** por roles: presión, cobertura, marcajes, desmarques y carreras al espacio, pases según líneas de pase libres,
  tiros según ángulo/distancia y uso ocasional de técnicas.
- Reglas básicas: saques de banda, de esquina y de arco, faltas por barridas, **penales** y un fuera de juego aproximado
  para colocar a los atacantes.

## Estructura

```
scenes/            main_menu.tscn, match.tscn (todo lo demás se construye por código)
scripts/autoload/  game_config (opciones/perfil), input_setup (mapeo de mando), fx (efectos)
scripts/core/      match (partido), player, ball, kick (trayectorias), team, human_controller, camera_rig, skill_db
scripts/ai/        team_ai (roles), player_ai (decisiones y portero)
scripts/ui/        hud, hud_widgets (barras, paleta R2, radar), main_menu
shaders/           césped, balón, red, público, líneas de velocidad
tests/             pruebas headless (física, controles, partidos IA vs IA, capturas)
docs/              documento de diseño y hoja de ruta
```

Para ajustar el "feel": velocidades y estamina en `player.gd` (`max_speed`, `_update_resources`), fuerza de tiros en
`_kick_shot`, energía por acción en `SkillDB.GAIN`, técnicas en `SkillDB.SPECIALS` y dificultad de la IA en `match.gd` (`ai_*`).

## Pruebas

```bash
GODOT=/ruta/a/godot tests/run_tests.sh
```

Incluye: precisión de pases/centros/tiros con efecto, porcentaje de atajadas del portero, una batería que simula el mando
(pase, tiro, tiro raso, amague, vaselina, regates, las 5 técnicas, despertar, quites, estamina) y partidos IA vs IA en los 4 formatos.

Más detalles de diseño y próximos pasos en [`docs/DISENO_GAMEPLAY.md`](docs/DISENO_GAMEPLAY.md).
