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
| Se recupera | Al no correr (4/s trotando, 7/s quieto) solo hasta el tope | Gol 160 (+20 al resto del equipo), asistencia 90, regate que supera al rival 40 (con L2: 55), esquivar un quite 30, atajada 30, quite/intercepción 25, tiro al arco 20, meter el pie 18, pase al hueco 16, resistir un quite 15, pase 10, amague 8 |
| Efecto | <12: más lento y sin sprint | — |

El tope baja un 12 % de lo gastado (escalado según la duración del partido) y nunca baja de 40.

## Acciones con balón

- **Stick = giroscopio.** El balón sale hacia donde apunta el stick.
- **Pase normal (Cruz):** al compañero *más cercano* dentro de un cono de 35° alrededor del stick (aro blanco bajo él). Si el
  stick no apunta justo al compañero, el balón sale en la dirección del stick (hasta 24° raso, 32° bombeado) y un solver
  numérico busca el efecto lateral necesario para que la curva termine en el receptor, adelantándose a su carrera.
- **Pase al hueco (Triángulo):** al espacio que hay delante del compañero mejor alineado, en la dirección del stick
  (aro amarillo). Sin compañero en esa dirección, el balón va al espacio hacia donde apuntas.
- **Tiro: intención.** El stick se proyecta sobre la línea de gol: si cae a más del 40 % del ancho desde el centro (hasta
  6 m por fuera del palo) se entiende como esa esquina; más cerca del centro, ese punto; más lejos, el tiro va afuera a
  propósito. La potencia fija la altura (poca = abajo, mucha = arriba). Sin stick, al palo contrario del portero.
- **Tiro: ruleta (backend).** Al disparar se calculan dos probabilidades:
  - *Ir al arco*: 0,5 + 0,45·Tiro − 0,014 por metro sobre 11 m − 0,18·presión − 0,45·exceso de potencia − ángulo
    cerrado, con modificadores por tipo (raso +0,05, curvo −0,15 + 0,3·Curva, vaselina −0,1, volea −0,15, cabezazo según
    Salto), −0,05 a la escuadra, −0,08 si estás agotado, +0,3 en técnicas. Si apuntaste afuera, 0.
  - *Que el portero no llegue*: velocidad del tiro, colocación, distancia lateral al portero frente a lo que puede cubrir en
    el tiempo de vuelo, Reflejos del portero, altura (abajo/arriba +0,06), Curva en tiros curvos y el bonus de rotura de
    las técnicas.
  Se tira el dado y el resultado (gol / atajada / afuera) queda guardado en el balón: el punto final se ajusta lo más cerca
  posible de donde apuntaste (lejos de las manos si es gol, a su alcance si es atajada, fuera del arco, sobre el travesaño
  o al palo si es afuera). Los defensas no pueden bloquear un tiro resuelto como gol y, si la física llevara adentro un tiro
  resuelto como atajada, el portero lo saca con la punta de los dedos al córner.

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

## Conducción y recepción

El balón conducido se mueve sobre el eje hacia donde mira el jugador: en cada toque se adelanta hasta una distancia máxima
(≈0,6 m al trote, ≈1 m esprintando para el humano; algo más para la IA), frena y el jugador lo vuelve a tocar. Cualquier
desvío lateral vuelve al eje enseguida, así que el balón nunca se va hacia un lado imprevisible. Con balón, el cuerpo gira
hacia donde apunta el stick; en giros de más de ~57° el jugador recoge el balón al pie y lo rodea con el cuerpo. Al proteger, frenar o armar un tiro, el balón vuelve al pie. Las recepciones
conservan entre el 4 % y el 35 % de la velocidad relativa del pase (primer toque) y el receptor humano camina solo hacia el
pase si no tocas el stick. El portero lleva el balón en las manos dentro de su área.

## Duelos: leer lo que pasa

- La IA anuncia cada intento de quite con un **"!" rojo** (0,28/0,20/0,14 s según dificultad) antes de lanzarse, y cancela si
  el rival ya se escapó.
- Esquivar (ventana de evasión de regates/amagues/técnicas): salto corto con estela, "¡ESQUIVA!" y el defensor queda
  descolocado 0,4 s. Aguantar un quite fallido: "¡RESISTE!". Perder el duelo: el jugador cae al suelo.
- Los avisos sobre la jugada se ordenan en renglones (máximo 3 a la vez) para no pisarse.

## Acciones sin balón

- **Quite (Círculo):** estocada corta. Éxito según quite vs. regate, fuerza, si protege (L2) y si vienes por detrás (posible falta).
  El que pierde el duelo cae al suelo.
- **Barrida (R1 + Círculo):** largo alcance, con polvo y aviso "¡BARRIDA!"; si tocas al rival antes que al balón es falta (penal en el área).
- **Meter el pie (Cuadrado):** estocada rápida que suelta el balón (no lo roba). Es más fácil si el rival lleva el balón lejos del pie.
- **Agarrar con el brazo (mantener Cuadrado al lado del rival):** lo frena y lo cansa; a los 0,7 s gana el duelo el más fuerte;
  si lo mantienes más de 1,6 s es falta.
- **Carga (Cruz):** duelo de fuerza + estamina hombro con hombro.
- **L2 marcar:** más lento pero con mayor radio de intercepción; con el stick quieto se coloca solo entre el portador y el arco.
- **L1 presionar:** corre solo hacia el portador (o al punto donde se cortará un balón suelto). En modo Equipo, un toque
  corto de L1 cambia al compañero que llega antes al balón.
- **Intercepciones** automáticas al pasar el balón cerca: probabilidad según atributo, velocidad del balón y si marcas.

## Técnicas especiales (paleta R2) y kit

El kit se arma en el menú (*Kit de habilidades*): 8 ranuras (R2 + botón y R2 + L2 + botón), cualquier técnica en cualquier
ranura (el Despertar solo una vez). Se guarda en `GameConfig.profile.palette` / `palette_l2`.

| Técnica | Tipo | Barras | Efecto |
|---|---|---|---|
| Disparo Directo | Tiro | 2 | 36 m/s, topspin y algo de *knuckle*; −35 % de probabilidad de atajada |
| Curva del Ego | Tiro | 2 | Sale por fuera y se cierra con muchísimo efecto; −40 % |
| Tiro Fantasma | Tiro | 2 | Sin rotación: baila en el aire (puede irse); −45 % |
| Meteoro Descendente | Tiro | 3 | Sube, curva y cae en picada a la escuadra; −55 % |
| Regate Fantasma | Regate | 1 | 1,3 s intocable a +40 % de velocidad; 60 % de tumbar a quien se cruce |
| Regate Relámpago | Regate | 1 | Zigzag de 4,5 m en 0,2 s hacia el stick (o lejos del rival), con estela |
| Sombrero Celestial | Regate | 2 | Balón por encima del rival (solo tu equipo puede tocarlo) y aceleración |
| Torbellino | Regate | 1 | Ruleta que derriba a los rivales a menos de 2,8 m |
| Pase Meteoro | Pase | 1 | Rasante a 28+ m/s; no se puede interceptar |
| Pase Bumerán | Pase | 1 | Sale abierto hacia el lado con menos rivales y se cierra al compañero; no se puede cortar |
| Centro Teledirigido | Pase | 1 | Centro a la cabeza del compañero, que remata de primera solo |
| Quite Relámpago | Defensa | 1 | Embestida a 19 m/s hasta 12 m: roba o captura el balón suelto |
| Muro de Acero | Defensa | 1 | 3 s bloqueando todo pase o tiro a 2,3 m (los pases especiales, al 50 %) |
| Despertar | Transformación | 3 | 20 s de "Flow" según el tipo elegido |

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

1. **Pulido del prototipo** (siguiente paso): probar con mando real y ajustar números; modelos con esqueleto real y
   animaciones capturadas, sonido (golpeo, público, gritos de técnicas), mejor cámara en córners/penales, fuera de juego real y tarjetas.
2. **Creador de personaje** estilo Xenoverse 2: cuerpo, cara, pelo, botines; reparto de puntos de atributo; equipar técnicas en
   las ranuras R2 / R2+L2; elegir tipo de Despertar.
3. **Modo carrera "Blue Lock"**: selecciones por rondas, partidos 1v1/3v3/5v5/11v11, ranking, rivales con ego propio,
   progresión por experiencia, desbloqueo de técnicas al cumplir retos (p. ej. "marca de volea" desbloquea una volea especial).
4. **Contenido**: más técnicas (combinadas entre dos jugadores, especiales de portero), estadios, uniformes, clima.
5. **Online/local multijugador** (varios mandos ya están soportados por el mapeo, falta asignar un jugador por mando).
