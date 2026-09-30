# Cómo funciona Spray por dentro

## La regla que decide todo lo demás

Spray no integra nada. No hay un bucle que diga `posicion += velocidad * dt`. Hay un número, el reloj, y todo lo que ves en pantalla se *evalúa* desde ese número.

Esa decisión suena pequeña y no lo es, porque de ella salen tres propiedades gratis: no hay deriva por framerate (nada se acumula, así que nada se desfasa), `:SetTime(3.2)` da exactamente el mismo cuadro que habrías obtenido reproduciendo hasta 3.2 segundos, y el reloj puede ir hacia atrás. Un `:Forward(-0.2)` no es una aproximación ni una reconstrucción: es evaluar la misma fórmula con un `t` menor.

El precio es que cada cosa que dependa del pasado hay que eliminarla o convertirla en dato. Por eso los `:Emit()` se guardan como `{Time, Count, Index}` en vez de generar partículas, y por eso `LockedToPart = false` no está implementado (necesitaría recordar dónde estaba el padre en el momento del spawn, y eso es historia).

## El random que no es un random

Un generador normal tiene estado: le pides el siguiente número y avanza. Eso no sirve acá, porque para dibujar el instante `t` hay que poder preguntar "¿qué velocidad le tocó a la partícula 400?" sin haber pasado por las 399 anteriores.

La solución es reemplazar el generador por una función hash pura:

```
Unit(Seed, Index, Channel) → [0, 1)
```

Mismos tres argumentos, mismo número, siempre, en cualquier orden. Por dentro es el finalizador de splitmix32 aplicado dos veces:

```lua
mixed = Mix32(Seed ⊕ (Index+1) * 0x9E3779B1)
return Mix32(mixed ⊕ (Channel+1) * 0x85EBCA77) / 2^32
```

La primera línea solo depende de la semilla y de la partícula, así que el código la parte en dos: `Sampling.Stream(Seed, Index)` hace el primer `Mix32` y `Sampling.Unit(Stream, Channel)` el segundo. `Derive` saca el stream una vez y lo reutiliza para los catorce canales que sortea, con lo que el nacimiento de una partícula cuesta la mitad. Los números que salen son los mismos de antes de partirlo, porque la cuenta es la misma.

Las constantes `0x9E3779B1` y `0x9E3779B9` son la proporción áurea escalada a 32 bits, la de siempre en mezcladores de este tipo; sirve porque sus bits no tienen patrón y multiplicar por ella riega el índice por todo el ancho de la palabra.

Dos detalles que valen la pena:

**`Multiply32` multiplica partiendo los operandos en mitades de 16 bits.** Un `double` tiene 53 bits de mantisa, y multiplicar dos números de 32 bits da hasta 64, así que hacerlo directo pierde los bits bajos en silencio. Los bits bajos son justo los que el hash necesita, por lo que el síntoma no es un error sino partículas que salen agrupadas. Partir en mitades y recombinar mantiene cada producto parcial por debajo del límite.

**El `Channel` existe para aislar decisiones.** Cada propiedad que se sortea tiene su propio canal: `CHANNEL_SPEED = 2`, `CHANNEL_LIFETIME = 1`, `CHANNEL_SPREAD = 3`, y así hasta 14. Sin esa separación, tocar el rango de velocidad en el emisor cambiaría el flujo completo y con él la vida, el ángulo y la rotación de cada partícula. Con canales, mueves `Speed` y lo único que se mueve es la velocidad.

## Quién existe en el instante t

La partícula `i` del flujo continuo nace en `i / rate`. Nada más. De ahí sale que las que podrían estar vivas en el reloj `c` son una ventana acotada:

```lua
newest = floor(c * rate)
oldest = max(0, ceil((c - maxLifetime) * rate))
```

Se recorre ese rango y ya. No hay lista de partículas vivas, no hay que insertar ni borrar de ninguna estructura, y el costo por cuadro no depende de cuánto lleve corriendo el efecto.

`maxLifetime` es `Lifetime.Max`, no la vida real de cada partícula, porque el rango tiene que ser correcto antes de saber qué le tocó a cada una. La que ya murió se descarta después, en `Resolve`, cuando `age >= Lifetime` devuelve `false`.

Ojo con eso, porque una ráfaga se queda en la ventana hasta que se cumple la vida más larga posible, y las partículas que murieron antes siguen apareciendo en el recorrido durante varios frames. Si una de esas no tiene slot, `Visit` la descarta antes de pedir uno, con un solo hash (`Simulation.Lifetime`). Antes pedía slot, se derivaba completa y lo devolvía, en cada frame; con ráfagas grandes eran más de mil derivaciones por frame que no dibujaban nada.

El `rate` se recorta contra el techo del pool con `min(Rate, MaxParticles / maxLifetime)`. La población en equilibrio de un flujo continuo es `rate × lifetime`, así que esa división es literalmente despejar `rate` de `poblacion ≤ MaxParticles`. Sirve sobre todo porque los emisores que solo se usan para ráfagas suelen tener el `Rate` abandonado en un valor absurdo.

Las ráfagas se recorren aparte y se saltan con un `continue` si el reloj está fuera de su ventana.

`:Emit()` dibuja solo la ráfaga nueva. Lo demás ya está donde lo puso el reloj, y redibujar el emisor completo en cada `:Emit()` hacía que las ráfagas seguidas sobre un efecto cargado costaran un frame extra cada una. Peor todavía, era un costo que crecía justo cuando el juego iba lento, porque con frames más largos caen más ráfagas por frame.

**Las llaves.** Cada partícula se identifica con un entero, y el esquema evita colisiones sin coordinación:

```
flujo continuo:  index * 2                                      (pares)
ráfagas:         (burstIndex * MaxParticles + offset) * 2 + 1   (impares)
```

La paridad separa los dos orígenes y el `burstIndex * MaxParticles` separa las ráfagas entre sí, porque `Count` está limitado a `MaxParticles` en `:Emit()`. Dos ráfagas simultáneas no se pisan aunque nazcan en el mismo segundo.

## Dónde nace cada partícula

Con `EmissionSize` en cero es un emisor puntual y no hay nada que calcular. Ese es el caso común, y además es cómo se comporta un emisor 3D colgado de un Attachment.

Con área, el módulo sortea dos números `u` y `v` y de ahí salen la posición y la normal.

**Caja, volumen.** Trivial: `(u*2-1) * halfWidth`.

**Caja, superficie.** Acá hay una trampa que el código esquiva. Lo obvio sería elegir un borde y luego un punto en él, pero eso reparte la mitad de las partículas en los bordes cortos y la otra mitad en los largos, así que en un rectángulo alargado los lados cortos quedan con densidad mucho mayor. La versión correcta camina el perímetro por longitud de arco:

```lua
perimeter = 2 * (halfWidth + halfHeight)
walk = u * perimeter
```

Ojo que ese `perimeter` es la mitad del perímetro real; recorre un borde horizontal y uno vertical, y luego usa `v < 0.5` para espejar al borde opuesto. Menos aritmética, misma uniformidad.

**Esfera, cilindro y disco** colapsan todos a la misma elipse en 2D, y se tratan igual:

```lua
angle  = u * 2π
radius = Surface and 1 or sqrt(v)
x = cos(angle) * radius * halfWidth
y = sin(angle) * radius * halfHeight
```

La raíz de `v` es el truco clásico y es el que más se olvida. Si usas `v` directo, el área de un anillo crece con el radio pero le sigues dando la misma probabilidad, entonces el centro queda apeñuscado y el borde vacío. `sqrt` es la inversa de la CDF de la distribución uniforme en el disco, y deja el relleno parejo.

**La normal no es el radio.** Este detalle solo aparece cuando la elipse no es un círculo. La dirección hacia afuera de `x²/a² + y²/b² = 1` es el gradiente:

```lua
∇ = (x / a², y / b²)   normalizado
```

En un círculo `a = b` y el gradiente es paralelo al radio, por eso es fácil no darse cuenta; en una elipse ancha la diferencia es visible y las partículas saldrían torcidas respecto a la superficie.

La caja no hace nada de esto: una cara emite a través de sí misma, no alejándose de su centro, así que la normal es la `EmissionDirection` autorizada.

`ShapeInOut` invierte el signo, y en `InAndOut` la moneda se lanza con su propio canal (`CHANNEL_SHAPE_SIGN`) para que la decisión sea estable al rebobinar.

## El spread

Una rotación 2D normal, con el ángulo sorteado simétrico alrededor de la dirección base:

```lua
angle = rad((u*2 - 1) * SpreadAngle)
nuevoX = dx*cos - dy*sin
nuevoY = dx*sin + dy*cos
```

`SpreadAngle` es el semiángulo, así que 180 es el círculo completo. Es el valor con el que está autorizada casi cualquier explosión.

## El movimiento: la fórmula cerrada

Acá está el corazón. Con arrastre lineal `k` y aceleración constante `a`, la ecuación es

```
dv/dt = a - k·v
```

que se integra a

```
v(t) = a/k + (v₀ - a/k)·e^(-kt)
p(t) = (a/k)·t + (v₀ - a/k)·(1 - e^(-kt))/k
```

`a/k` es la velocidad terminal, el punto donde el arrastre cancela la aceleración. En el código se llama `terminalX/Y`, y `restX = v₀ - terminal` es lo que sobra de la velocidad inicial, que es lo que decae. El factor `(1 - e^(-kt))/k` está guardado como `settled` y se puede leer como un "tiempo efectivo": empieza valiendo `t` y se satura en `1/k` cuando la partícula ya llegó a su terminal.

Cuando `k → 0` la expresión tiende a `v₀t + at²/2`, o sea el tiro parabólico de toda la vida. Las dos ramas coinciden en el límite, entonces `DRAG_EPSILON = 1e-4` no cambia el resultado, solo decide qué aritmética corre y evita dividir por casi cero.

El `clamp` del exponente a ±60 es defensa contra `Drag` negativo. Con `k < 0` el exponente `-kt` se vuelve positivo y crece, `exp` devuelve infinito, infinito por cero da NaN y una posición NaN hace que el ImageLabel simplemente desaparezca sin error. Con el tope, un `Drag` mal puesto se ve feo pero se ve.

La función devuelve posición y velocidad en la misma pasada porque comparten `decay` y los términos terminales, y porque la velocidad se necesita después para orientar la partícula.

## Tamaño y squash

El `squash` de Roblox es un estiramiento sobre el eje largo de la partícula, y el código lo resuelve manteniendo el área:

```lua
long  = 1 + |squash|
short = 1 / long
```

Como `long * short = 1`, el producto ancho×alto no cambia sin importar cuánto estires. El signo decide qué eje se lleva el `long`.

## Rotación y orientación

Esta parte es la más fácil de invertir por accidente. En espacio GUI, `+Y` apunta hacia abajo y la rotación es positiva en sentido horario; con esas dos convenciones, rotar el vector `(0,1)` por θ da `(-sin θ, cos θ)`. Igualando eso a la velocidad normalizada se despeja:

```lua
aligned = deg(atan2(-vx, vy))
```

que es el ángulo que pone el `+Y` local de la partícula — su eje largo si está aplastada, y hacia dónde apunta una textura de estela — a lo largo del movimiento.

Pero Roblox no usa ese eje. En `VelocityParallel` alinea el `X` local con la velocidad, no el `Y`, así que la base real es `aligned - 90`:

```lua
rotation = Rotation + RotationSpeed * age + (aligned - 90)
if VelocityPerpendicular then rotation += 90 end
```

El comentario en el código explica por qué importa y tiene razón: un emisor de estelas se autoriza como `VelocityParallel` con `Rotation = 90`, y ese 90 es precisamente lo que trae el eje largo de vuelta sobre la velocidad. Si tomas `aligned` como base, cada emisor de ese tipo sale girado un cuarto de vuelta y las estelas quedan atravesadas al movimiento en lugar de a lo largo.

Las dos orientaciones `FacingCamera*` se saltan el bloque entero, porque en 2D ya están mirando a cámara por construcción.

## Secuencias y el envelope

`NumberSequence` y `ColorSequence` se leen con interpolación lineal entre keypoints, con un escaneo lineal en vez de búsqueda binaria porque Roblox tapa las secuencias en 20 puntos y a esa escala el escaneo gana.

Lo que se escanea no es el tipo del motor. Pedirle `.Keypoints` a un `NumberSequence` arma una tabla nueva con objetos nuevos en cada acceso, y eran cuatro accesos por partícula por frame (tamaño, squash, transparencia y color). `Spec.Read` convierte cada secuencia una sola vez en una curva, que es una tabla plana de `{Time, Value, Envelope}`, y `Sampling.Number` y `Sampling.Color` leen esas. En el benchmark, eso por sí solo bajó cerca de un quinto el costo de mantener partículas en pantalla.

Lo interesante es el envelope. Roblox lo define como una banda de ±`Envelope` alrededor del valor, y Spray lo resuelve así:

```lua
valor_final = valor + envelope * EnvelopeRoll
```

donde `EnvelopeRoll ∈ [-1, 1]` se sortea **una vez** en `Derive` y se queda fijo toda la vida de la partícula. Esa es la diferencia entre que el envelope se lea como variación entre partículas — unas más grandes, otras más pequeñas, cada una consistente consigo misma — y que se lea como ruido temblando cuadro a cuadro. Hay tres rolls independientes, uno para tamaño, uno para transparencia y uno para squash.

El envelope también se interpola entre keypoints, no solo el valor, así que una banda que se abre a la mitad de la vida se abre suave.

`IsFlatColor` recorre los keypoints y, si todos son iguales, el renderer se salta la lectura de secuencia y la escritura de `ImageColor3` por partícula por cuadro. La mayoría de emisores tienen color plano, así que paga.

## Flipbook

`FlipbookFrames` guarda las frames por fila, entonces el total es `rows²`: un `Grid4x4` son 16 celdas. El recorte se calcula en fila mayor:

```lua
edge = FlipbookResolution / rows
offsetX = ((cell-1) % rows) * edge
offsetY = floor((cell-1) / rows) * edge
```

Los cuatro modos:

- **OneShot**: una sola pasada estirada sobre la vida. `span = N - start + 1`, y `cell = clamp(start + floor(progress * span), 1, N)`. El clamp atrapa el `progress = 1` exacto, que si no se pasaría una celda.
- **Loop**: `1 + (start - 1 + elapsed) % N`, con `elapsed = floor(age * rate)`.
- **PingPong**: una onda triangular de periodo `2N - 2`. El `-2` es lo que evita que las celdas de los extremos se repitan dos veces al dar la vuelta.
- **Random**: acá está lo bueno. En vez de llamar `math.random`, hashea sobre la *ventana* de tiempo, usando `CHANNEL_FLIPBOOK_RANDOM + elapsed * 32` como canal. Dentro de una misma ventana el resultado es constante, y rebobinar sobre una partícula le muestra exactamente las mismas celdas que mostró la primera vez. El `* 32` solo separa las ventanas lo suficiente para que no se solapen con los otros catorce canales.

## Unidades: cómo un stud se vuelve píxeles

Un stud vale, por defecto, la altura en píxeles del GuiObject padre. Eso hace que el efecto escale con la UI en la que vive en vez de con la pantalla, entonces sobrevive un resize y un celular sin tocar nada. `SprayUnit` cambia qué borde se toma (`RelativeXX`, `RelativeMin`, `RelativeMax`, o `Offset` para 1 stud = 1 píxel).

La posición final mezcla dos escalas distintas a propósito:

```lua
Frame.X = OffsetX * ParentWidth + offsetX * (pixelsPerStud * SpeedScale)
```

El primer término es el punto de nacimiento, guardado como *fracción* del padre, porque `SprayEmissionSize` está autorizado en fracciones y así el área de emisión sigue al padre cuando cambia de tamaño. El segundo es el desplazamiento físico, que viene de la velocidad y por eso lo multiplica `SpeedScale`, no `SizeScale`. `SprayScale` multiplica los dos.

`PixelsPerStud` se recalcula cada cuadro en vez de guardarse en el spec, porque el padre cambia de tamaño con el viewport y un valor cacheado deja partículas del tamaño equivocado hasta que algo fuerce un rebuild.

## El color: emulando luz sin blending aditivo

La GUI de Roblox tiene un solo modo de mezcla, alpha over. No existe una ruta aditiva que pedir, así que `LightEmission` no se puede honrar literalmente y se emula por dos lados.

**Tone mapping.** Siempre activo, y es lo que más aporta:

```lua
rgb = color * Brightness
peak = max(r, g, b)
if peak > 1 then
    graded = (rgb / peak):Lerp(WHITE, 1 - 1/peak)
end
```

La lógica es que un canal que se sale del rango no tiene a dónde ir sino al blanco. Se renormaliza para conservar el tono y después se arrastra hacia blanco por cuánto hubo que botar. Con `Brightness = 2` el arrastre es 0.5; con 15 es 0.933, o sea un núcleo casi blanco con un tinte apenas visible, que es exactamente cómo se ve una partícula aditiva reventada. Antes de esto había que autorizar la textura ya quemada.

`Brightness` y `LightEmission` se mantienen separados a propósito. Es tentador amarrarlos, y el efecto de amarrarlos sería aplanar todo lo que esté autorizado brillante pero sin emisión: un destello de impacto en `Brightness 4` saldría como un color medio y plano en vez del crema quemado que le toca.

**Capas de halo.** Opcional vía `SprayGlowLayers`. Cada anillo extra crece y se desvanece en progresión geométrica:

```lua
growth  = 1 + 0.45 * step
opacity = (1 - transparency) * 0.45^step * LightEmission
```

Van en `ZIndex` menor que el núcleo para no taparlo. El `* LightEmission` al final es lo que hace que un emisor que no dice emitir luz no reciba halo.

Ninguna de las dos cosas hace que dos partículas superpuestas *sumen* como sumaría el aditivo real. Nada disponible para un GuiObject lo hace. Sobre los paneles oscuros donde suelen ir estos efectos la diferencia es chica.

## El pool y la identidad por llave

`Acquire(key)` devuelve el slot que ya tiene esa llave, o uno libre, o `nil` si se llegó al techo. Un slot reciclado todavía carga las constantes de la partícula anterior, y el llamador se da cuenta porque `slot.Constants.Key ≠ key`, entonces vuelve a derivar. Esa comparación es todo el mecanismo de "esta es una partícula nueva", sin banderas ni eventos.

Cada pasada tiene un número (`_pass`) y cada slot que se dibuja queda marcado con él. Al final se recorre `Active` y se libera cualquier slot con una marca vieja. Antes era un set de llaves que se vaciaba y se volvía a llenar en cada frame, y medido costaba unos 200 ns por partícula, más que varias de las cuentas. Los slots a liberar se juntan en una lista primero porque liberar muta la tabla que se está recorriendo.

`Renderer.Prewarm` construye slots por adelantado y los deja directamente en la lista de libres, así que la primera ráfaga de un efecto los encuentra hechos. Crear los ImageLabels es casi todo lo que cuesta esa primera ráfaga, y así ese costo se puede pagar en una pantalla de carga. `:Prewarm()` lo llama con la cantidad que se le pida, y `SprayPrewarm` lo hace cada vez que el Spray se construye.

Las constantes se escriben *dentro* de la tabla existente (`Derive(..., Into)`) en vez de reemplazarla, y `Resolve` escribe en un único `ParticleFrame` que vive en el Spray. Con eso, recorrer 400 partículas no crea tablas nuevas. Sí crea los `UDim2` que piden `Position` y `Size`, que no hay forma de evitar.

El renderer además recuerda lo último que le escribió a cada ImageLabel (`Written` en el slot) y se salta toda escritura que no cambie nada. Escribir una propiedad cuesta del orden de 700 ns, y comparar dos números casi nada, así que un emisor con color plano, sin giro o con tamaño fijo se ahorra varias escrituras por partícula en cada frame. La visibilidad también se lleva ahí, porque leer `.Visible` de vuelta es otra llamada al motor.

## Dos rarezas del motor que el renderer tiene que rodear

Estas no son matemática pero son muy específicas y se ven raras si no sabes de dónde salen.

Un `ImageLabel` oculto descarta las asignaciones de `ImageRectSize`. Por eso `Visible = true` se pone *antes* de escribir cualquier otra cosa: si no, una partícula de flipbook cuyo primer cuadro dibujado es también su primer cuadro visible se queda sin recorte y muestra la hoja de sprites completa. Todo lo demás se escribe en ese mismo cuadro, así que nada alcanza a verse sin posicionar.

Relacionado: el motor también descarta un `ImageRectSize` puesto contra una textura que todavía no terminó de resolver, y no hay forma de preguntar si la asignación pegó. Entonces el recorte se reafirma cada cuadro en vez de confiarse del que se puso al construir el slot. Cuesta una escritura extra, solo en emisores con flipbook. Queda un cuadro que esto no cubre —el primerísimo de la primera ráfaga, con la textura aún en vuelo— y como los slots se reciclan, no puede volver a pasar después.

## Pendiente

`ShapePartial` y `VelocityInheritance` se leen en `Spec.Read` y se guardan en el snapshot, pero nadie los consume. El encabezado de `init.luau` dice que toda propiedad del ParticleEmitter está implementada, y con esas dos no se cumple.
