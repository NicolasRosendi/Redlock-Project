# Arte y assets: cómo llegar al look "anime pseudorrealista"

## ¿Godot o Unity?

**Seguimos en Godot 4.** El motor no es el límite: Godot 4 (renderer Forward+) tiene todo lo necesario para un juego de
fútbol anime de alto nivel: shaders toon propios, contornos, glow/bloom, SSAO, partículas por GPU, animación esquelética con
retargeting, árboles de animación (blend de carrera/regates) e importación directa de glTF/VRM. Pasar a Unity obligaría a
rehacer todo el gameplay (física del balón, IA, ruleta de tiros, técnicas, HUD) y no aportaría nada que hoy nos falte.

Lo que separa al prototipo de un juego "épico" es **el arte** (modelos, animaciones capturadas, VFX dibujados), no el motor.

## Lo que ya está hecho por código (sin assets externos)

- **Sombreado anime** (`shaders/toon.gdshader`): dos tonos con sombra tintada, brillo especular duro y luz de borde.
- **Contorno cel-shading** (`shaders/outline.gdshader`) en todo el cuerpo.
- **Cabeza anime**: ojos grandes con iris y brillo, cejas, boca y pelo en puntas en dos capas, distinto en cada jugador.
- **Dragón de energía** (`scripts/fx/energy_dragon.gd` + `shaders/dragon.gdshader`): cuerpo serpenteante con escamas,
  aletas dorsales, cabeza con cuernos, colmillos, bigotes y ojos brillantes; lleva el balón entre las fauces.
  Aparece en tiros especiales (grande), pases especiales (serpiente pequeña) y al despertar (se enrosca en el jugador).
- **Aura de llamas** del Despertar (`shaders/aura.gdshader`), glow y tonemapping ACES, torres de focos.

## Siguiente salto: personajes reales (fuentes legales)

> **No usar assets de Rocket League, Roblox ni de otros juegos.** Son propiedad de Epic/Psyonix, Roblox, etc.; extraerlos
> para otro juego infringe sus derechos y términos de uso, y bloquearía cualquier publicación del juego.

| Necesidad | Fuente recomendada | Licencia | Cómo entra en Godot |
|---|---|---|---|
| Personaje anime personalizable (cara, pelo, ropa) | **VRoid Studio** (gratis, de pixiv) | Uso comercial permitido con tus modelos | Exportar `.vrm` → addon **godot-vrm** (MIT) |
| Animaciones (correr, patear, barrida, celebrar) | **Mixamo** (Adobe, gratis) | Uso en juegos permitido | FBX → Blender → glTF, retarget al esqueleto humanoide de Godot |
| Animaciones de fútbol específicas | Captura con **Rokoko Video** / **Move.ai** (desde un video) | Según plan | FBX → retarget |
| Efectos (dragones, fuego, rayos) | **Fab** (Epic), **Unity Asset Store** (verificar que la licencia permita otros motores), artistas en **ArtStation** por encargo | Comercial | Texturas/flipbooks y meshes en glTF |
| Utilería, estadio, CC0 | **Kenney**, **Quaternius**, **Poly Haven** | CC0 | glTF directo |

### Plan propuesto para el creador de personajes (estilo Xenoverse 2)

1. Hacer en VRoid 2–3 cuerpos base y una biblioteca de peinados, caras y botines.
2. Importar con godot-vrm y unificar todo al esqueleto humanoide de Godot (`SkeletonProfileHumanoid`).
3. Reemplazar el cuerpo procedural de `Player._build_visual()` por el modelo, manteniendo la misma interfaz
   (estados → animaciones en un `AnimationTree`). La lógica de juego no cambia.
4. El editor de kit del menú pasa a ser también el editor de apariencia (pelo, color, cara, botines).

Con ese pipeline el juego puede verse como un anime 3D moderno sin cambiar de motor.
