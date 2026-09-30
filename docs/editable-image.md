# EditableImage como renderer opcional

Esto es una propuesta y no hay nada implementado. Los números salen de una sonda corrida en Studio en el place del playground, y lo que no se midió está marcado como tal.

## Qué ganaría Spray

Lo más valioso es el aditivo de verdad. `EditableImage` tiene `Enum.ImageCombineType.Add`, y en la sonda funcionó con el mismo costo que el alpha normal. Hoy `LightEmission` se emula con tone mapping y halos, y el README lo pone en las limitaciones porque las partículas superpuestas no suman. Con un canvas sí sumarían, y los halos de `SprayGlowLayers` pasarían a ser bloom de verdad.

Lo segundo es tener menos instancias, porque sería un ImageLabel por host en vez de uno por partícula (y por capa de halo).

Lo tercero es que abre la puerta a buffers y Actors. Hoy no rinden porque el 83% del frame son escrituras de propiedades que solo pueden hacerse en serie (ver [optimization.md](optimization.md)). Si el dibujo pasara a ser cálculo sobre un buffer, ese cálculo sí se podría repartir.

## Lo que midió la sonda

| Prueba | Resultado |
| --- | --- |
| Crear un canvas de 512×512 con `AssetService:CreateEditableImage` | Funciona en este place |
| Mostrarlo con `ImageLabel.ImageContent = Content.fromObject(canvas)` | Funciona |
| Limpiar el canvas completo con `WritePixelsBuffer` | 0.11 ms |
| Limpiar y dibujar 1000 partículas con `DrawImageTransformed` (sprite de 32 px escalado a 20, rotado) | ~32 ms, igual con `AlphaBlend` que con `Add` |
| Lo mismo con ImageLabels (Spray actual) | ~5.8 ms |
| Cargar `rbxasset://textures/particles/sparkles_main.dds` | Falla con "unexpected format" |

La conclusión directa es que dibujar partícula por partícula con el motor es unas cinco veces más lento que los ImageLabels, así que no sirve como reemplazo general. Además, `DrawImageTransformed` recibe posición, escala, rotación y opciones (`CombineType`, `SamplingMode`, `PivotPoint`), pero ni color ni transparencia por llamada. Un fade o un gradiente por partícula necesitaría copias pre-teñidas del sprite.

## Dos formas de dibujar

**A. `DrawImageTransformed` por partícula.** Es lo más simple de integrar y usa al motor para rotar y escalar. A ~32 µs por partícula solo tiene sentido para efectos chicos donde el aditivo importa más que la cantidad, como un destello o un glow de 20 a 50 partículas. El color y la transparencia habría que resolverlos con variantes del sprite cuantizadas, por ejemplo 16 niveles de transparencia por color, cacheadas.

**B. Un rasterizador propio.** Spray escribiría los píxeles de todas las partículas en un `buffer` y haría un solo `WritePixelsBuffer` por frame. El color, la transparencia y el aditivo pasan a ser cuentas, y la escritura al motor es una llamada en vez de miles. Con Actors encaja bien si el canvas se parte en franjas: cada Actor es dueño de su franja, con su propio EditableImage y su propio ImageLabel, y rasteriza solo las partículas que la tocan. Así no hay que compartir memoria entre Actors, y cada uno hace su `WritePixelsBuffer` al sincronizar.

El costo de B no está medido y es lo primero que hay que medir. A ojo, 1000 partículas de 20 px son unos 300 mil píxeles mezclados por frame, y la pregunta es si Luau nativo leyendo y escribiendo en un buffer puede hacer eso en pocos milisegundos. Si no puede, B no vale la pena.

## Por qué tiene que ser opcional

Un place puede tener desactivada la API de EditableImage, y la creación también puede fallar por memoria o por el dispositivo. Spray intentaría crear el canvas dentro de un `pcall`, y si falla volvería a los ImageLabels con un aviso en el output una sola vez.

La memoria pesa: un canvas cuesta ancho × alto × 4 bytes, o sea 1 MB a 512×512 y unos 8 MB a 1920×1080, por cada host. Un atributo como `SprayCanvasScale` permitiría dibujar a media resolución y dejar que el ImageLabel lo estire.

Las texturas también cambian. Las `.dds` que trae Roblox no cargan, así que el efecto necesita una textura PNG subida. Esto hay que revisarlo contra las reglas actuales de Roblox sobre qué assets se pueden cargar en un EditableImage, porque la sonda no lo verificó.

Además, las partículas quedarían todas en una sola capa, sin `ZIndex` propio, y lo que salga del canvas se corta. El canvas necesitaría un margen alrededor del host o cubrir el ScreenGui entero, parecido a lo que hace hoy `SprayIgnoreClips`.

## Cómo encajaría en Spray

El diseño actual ya lo deja fácil. `Simulation` y `Sampling` no tocan instancias, y `Resolve` llena un `ParticleFrame` que después lee el renderer, así que el renderer es el único punto que cambia. La idea sería:

- Un atributo `SprayRenderer` con `Labels` (el de hoy, por defecto) o `Canvas`.
- Un `CanvasRenderer` con las mismas funciones que `Renderer` (`Acquire`, `Release`, `Draw`, `Follow`, `Prewarm`, `Destroy`). Los slots seguirían existiendo como tablas con las constantes de cada partícula, pero sin ImageLabels. `Draw` guardaría el frame en una lista, y al final de `Render` se vacía todo al canvas de una vez.
- `Prewarm` solo tendría que crear el canvas.

## Por dónde empezaría

1. Medir B por separado, fuera de Spray: un rasterizador nativo con 1000 partículas de 20 px sobre un canvas de 512×512. Si pasa de unos 6 ms, los ImageLabels siguen ganando y B se descarta.
2. Si B rinde, repetirlo con 4 Actors por franjas y ver cuánto baja.
3. Solo entonces integrarlo como renderer opcional. Si B no rindiera, A todavía podría entrar como modo de calidad para efectos chicos que necesiten aditivo real.
