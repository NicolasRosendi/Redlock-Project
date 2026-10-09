# Diseño de gameplay — Redlock Project

Documento vivo. Resume las decisiones del prototipo y lo que viene después.

## Pilares

1. **Arcade en el control, creíble en la física.** El jugador decide *qué* hacer (pase, tiro, regate) y *hacia dónde*;
   el juego resuelve *cómo* (fuerza, curva, altura). Nada de dosificar el efecto a mano como en los juegos en primera persona.
2. **Lo normal se ve normal; lo especial se ve especial.** Pases y tiros comunes respetan la física. Las técnicas (R2) rompen
   la regla con cámara lenta, primer plano, líneas de velocidad, estela de color y onda expansiva, al estilo Captain Tsubasa.
3. **Dos recursos con propósitos distintos.** Estamina = cuerpo (correr, chocar, saltar). Energía = ego/espíritu (técnicas).
   La energía se gana *jugando bien*, no esperando.
4. **El jugador creado es el protagonista.** El modo Pro (solo tu jugador) es la base del futuro modo carrera.

## Recursos

| | Estamina | Energía |
|---|---|---|
| Rango | 0–100 con **tope** que baja con el cansancio | 5 barras × 100 |
| Se gasta en | Correr (6/s), presionar, marcar, quites (5), barridas (10), cargas (7), saltos (5), regates (5/9) | Técnicas R2 (1–3 barras) |
| Se recupera | Al no correr (4/s trotando, 7/s quieto) solo hasta el tope | Pase completado 10, al hueco 16, tiro al arco 18, quite 25, intercepción 25, regate exitoso 20, atajada 30, gol 60, asistencia 25, amague 5 |
| Efecto | <12: más lento y sin sprint | — |

El tope baja un 12 % de lo gastado (escalado según la duración del partido) y nunca baja de 40.

## Acciones con balón

- **Pase raso / bombeado / al hueco / centro.** El receptor se elige con un cono alrededor del stick (indicador blanco bajo
  el compañero). La fuerza se calcula para que llegue al pie del receptor *adelantándose a su carrera*; mantener el botón
  envía el balón más fuerte (y en los pases al hueco, más largo). La precisión depende del atributo de pase y de la presión.
- **Tiro.** Mantener carga la potencia (≈0,9 s). Más potencia = más alto; por encima del 85 % aparece error vertical (se va por
  arriba). Sin dirección en el stick apunta al palo contrario del portero. El efecto lateral se aplica solo cuando disparas
  cruzado respecto de tu carrera y es mayor en tiros suaves (colocados). El solver compensa la curva para que el balón termine
  donde apuntaste.
- **Tiro raso:** doble toque de Cuadrado (durante el armado del primer toque).
- **Vaselina:** L1 + Cuadrado.
- **Amague / cancelación:** tiro + Cruz (o pase + Cuadrado) durante la carga o el armado. Da 0,35 s de evasión y 5 de energía.
- **Remate de primera:** con el balón suelto acercándose, Cuadrado/Cruz dejan la acción "en cola"; al contacto se ejecuta como
  tiro, volea o cabezazo según la altura (salta solo si el balón viene alto).
- **Regates (stick derecho)**, relativos a hacia dónde mira el jugador:

| Dirección | Normal (5 est.) | Con L2 (9 est.) |
|---|---|---|
| Adelante | Toque largo (+15 % velocidad, balón suelto) | Sombrero (balón por encima, 0,7 s de evasión) |
| Lateral | Recorte (1,7 m, 0,3 s evasión) | Elástica (2,5 m, 0,48 s evasión) |
| Atrás | Arrastre (giro de 180°) | Ruleta (giro de 360° avanzando, 0,55 s evasión) |

  Mientras dura la evasión los quites fallan automáticamente. Si regateas cerca de un rival y conservas la posesión 1 s, ganas energía.

## Acciones sin balón

- **Quite (Círculo):** estocada corta. Éxito según quite vs. regate, fuerza, si protege (L2) y si vienes por detrás (posible falta).
- **Barrida (Cuadrado):** largo alcance; si tocas al rival antes que al balón es falta (penal dentro del área).
- **Carga (Cruz):** duelo de fuerza + estamina hombro con hombro.
- **L2 marcar:** más lento pero con mayor radio de intercepción; con el stick quieto se coloca solo entre el portador y el arco.
- **L1 presionar:** corre solo hacia el portador (o al punto donde se cortará un balón suelto).
- **Intercepciones** automáticas al pasar el balón cerca: probabilidad según atributo, velocidad del balón y si marcas.

## Técnicas especiales (paleta R2)

Ranuras equipables en `GameConfig.profile.palette` y `palette_l2` (base para la personalización). Las dos ranuras libres de
R2+L2 están reservadas para técnicas desbloqueables.

| Técnica | Barras | Efecto |
|---|---|---|
| Pase Meteoro | 1 | Pase rasante a 28+ m/s; los rivales no pueden tocarlo (salvo con Quite Relámpago, 50 %) |
| Quite Relámpago | 1 | Embestida a 19 m/s hasta 12 m: roba al portador o captura el balón suelto. Falla contra Regate Fantasma |
| Regate Fantasma | 1 | 1,3 s intocable a +40 % velocidad; 60 % de tumbar a los rivales que se crucen |
| Disparo Directo | 2 | 36 m/s, topspin y algo de *knuckle*; −35 % de probabilidad de atajada |
| Meteoro Descendente | 3 | Sube, curva y cae en picada a la escuadra; −55 % de probabilidad de atajada |
| Despertar | 3 | 20 s de "Flow" según el tipo elegido |

## Despertares

| Tipo | Efecto |
|---|---|
| Ego Cañonero | +0,3 potencia y precisión de tiro; tiros ×1,2 |
| Cuerpo de Acero | +0,35 fuerza y quite; estamina gasta 35 %, recupera ×3 |
| Alas de Cóndor | Salto ×1,45 (+0,6 atributo); cabezazos más fuertes |
| Velocidad Divina | +0,45 velocidad/aceleración, velocidad ×1,18, aceleración ×1,4 |
| Metavisión Predictiva | Marca dónde caerá el balón y la ruta ideal; seguirla da +25 % de velocidad. +0,4 intercepción |
| Visión Espacial | Radar con balón, trayectoria e intenciones rivales (pase, tiro, desmarque, presión); tus pases son la mitad de interceptables |

Todos además: +4 % de velocidad, recarga de estamina y aura visual.

## IA

- **TeamAI** reparte roles cada 0,15 s: portador, apoyo, presión, cobertura, marca (asignación voraz por cercanía a la zona
  propia), persecución del balón suelto (por tiempo de intercepción sobre la trayectoria prevista) y receptor.
- **PlayerAI**: el portador evalúa calidad de tiro (ángulo, distancia, bloqueos), líneas de pase (seguridad, espacio del
  receptor, progreso) y presión; regatea esquivando rivales. Los apoyos buscan espacios libres y los delanteros hacen
  carreras al hueco respetando la línea de fuera de juego. El portero se coloca en la bisectriz, predice el tiro y se lanza
  para llegar justo al punto de cruce.
- Dificultad: tiempo de reacción, tasa de quites, reflejos y bonus del portero rival.

## Hoja de ruta

1. **Pulido del prototipo** (siguiente paso): probar con mando real y ajustar números; animaciones (modelos con esqueleto
   y blend de carrera), sonido (golpeo, público, gritos de técnicas), mejor cámara en córners/penales, fuera de juego real y tarjetas.
2. **Creador de personaje** estilo Xenoverse 2: cuerpo, cara, pelo, botines; reparto de puntos de atributo; equipar técnicas en
   las ranuras R2 / R2+L2; elegir tipo de Despertar.
3. **Modo carrera "Blue Lock"**: selecciones por rondas, partidos 1v1/3v3/5v5/11v11, ranking, rivales con ego propio,
   progresión por experiencia, desbloqueo de técnicas al cumplir retos (p. ej. "marca de volea" desbloquea una volea especial).
4. **Contenido**: más técnicas (combinadas entre dos jugadores, especiales de portero), estadios, uniformes, clima.
5. **Online/local multijugador** (varios mandos ya están soportados por el mapeo, falta asignar un jugador por mando).
