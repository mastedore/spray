# Cómo se optimizó Spray

El primer borrador del post del DevForum decía que Spray rendía mucho mejor que las otras librerías de partículas para UI, pero reconozco que esa frase no tenía ningún número detrás. Así que lo primero fue medirla. Armé el mismo efecto en Spray y en Emitter2D (misma textura, curvas, velocidad, gravedad y tamaño en pantalla), 10 emisores, y medí cuánta CPU gastaba cada una por frame.

El resultado inicial no daba para presumir. Manteniendo 1000 partículas en pantalla empataban (9.2 ms contra 9.4 ms), y con ráfagas seguidas Spray perdía, en una corrida 22 ms contra 14 ms y en otra 67 contra 16.

## Medir bien antes de tocar nada

Lo primero que salió a la luz fue que los tiempos absolutos no sirven. La misma prueba daba el doble de rápido o el doble de lento según el minuto, porque la máquina cambiaba de ritmo a mitad de corrida. Lo que sí se mantenía era la proporción entre las dos librerías cuando corrían una pegada a la otra, así que el benchmark quedó armado alrededor de eso: cada prueba corre en orden A B B A, o en rondas alternadas, y se queda con la mediana. Emitter2D pasó a ser la regla fija contra la que se mide cualquier cambio.

Después vino el piso, es decir, lo que cuesta cada operación suelta, medido en un bucle:

| Operación | Costo |
| --- | --- |
| Escribir una propiedad de un ImageLabel | ~700 ns |
| Una tirada del hash (`Sampling.Unit`) | ~450 ns |
| Insertar en un set y vaciarlo | ~200 ns |
| `Color3:Lerp` | ~80 ns |
| Leer `.Visible` | ~80 ns |
| `UDim2.fromOffset` | ~50 ns |
| Leer `.X` y `.Y` de un Vector2 | ~18 ns |
| Leer un Enum | ~8 ns |

Esa tabla explica casi todo lo que vino después. Una partícula que cambia posición, tamaño, rotación, transparencia y color necesita 5 escrituras, o sea unos 3.5 µs que ninguna librería se puede saltar. Todo lo demás se mide contra eso.

## Las tres causas grandes

La primera estaba en cómo se leían las secuencias. `Sampling.Number` le pedía `.Keypoints` al `NumberSequence` cada vez, y Roblox arma una tabla nueva con objetos nuevos en cada acceso. Eran cuatro accesos por partícula por frame (tamaño, squash, transparencia y color). Convertir cada secuencia una sola vez en una tabla plana bajó el costo de mantener 1000 partículas de 9.2 a 7.5 ms.

La segunda eran partículas muertas que seguían trabajando. Una ráfaga se queda en la ventana de búsqueda hasta que se cumple la vida más larga posible, y las que morían antes volvían a pedir un slot, a derivar sus constantes completas (unas catorce tiradas de hash) y a devolverlo, en cada frame. Con ráfagas grandes medí 1403 derivaciones por frame cuando solo hacían falta 274. Ahora una partícula muerta sin slot se descarta con una sola tirada, antes de tocar el pool.

La tercera fue la más traicionera. `:Emit()` redibujaba el emisor completo y no solo la ráfaga nueva. Eso cuesta un frame extra por ráfaga, y con el juego a 60 fps casi no se nota, pero a 10 fps las ráfagas caen cada dos o tres frames y el redibujado empieza a pesar más, lo que baja más los fps. Era un costo que crecía justo cuando el juego ya iba lento, y por eso las corridas daban números tan distintos entre sí.

## Las pequeñas

La tabla de costos también señaló cosas menores. El set de partículas vistas (`_seen`) se vaciaba y se volvía a llenar cada frame por unos 200 ns por partícula, y se cambió por un número de pasada guardado en el slot. El hash se partió en dos, porque su primera mitad solo depende de la semilla y de la partícula, así que ahora se calcula una vez y se reutiliza para los catorce canales, y el hash de cada partícula nueva cuesta cerca de la mitad. Los módulos que corren cada frame se compilan con `--!native`. Los enums se leen una sola vez, aunque ahí la tabla ya decía que se ganaba poco.

## Lo que más rindió fue no escribir

Si escribir es lo caro, lo que más sirve es escribir menos. Ahora el renderer recuerda lo último que le escribió a cada ImageLabel y se salta toda escritura que no cambie nada. En el efecto del benchmark las cinco propiedades cambian en cada frame, así que ahí se nota poco. En un efecto más típico de UI, con color plano y sin giro, Spray pasa a escribir tres propiedades por partícula mientras Emitter2D sigue escribiendo diez, y la diferencia sube a 1.7 veces.

## Lo que se probó y no rindió

Buffers y Actors sonaban bien y se midieron antes de decidir nada.

Quitando las escrituras, todo el cálculo de Spray para 1000 partículas cuesta 1.0 ms de un frame de 5.8 ms. Las escrituras son el 83%.

Con buffers, un núcleo de cinemática sobre buffers corrió 2.7 veces más rápido que sobre tablas (0.031 contra 0.083 ms por 1000 partículas). El problema es que eso ahorra 0.05 ms de 5.8, menos del 1%.

Con Actors pasa algo parecido. En paralelo se puede calcular, pero no se pueden modificar instancias, así que las escrituras siguen en serie. Un prototipo con 4 Actors y 2000 partículas cada uno, calculando en paralelo y escribiendo después de `task.synchronize()`, empató con la versión en serie: una ronda ganó el paralelo (30.7 contra 33.2 ms) y la otra el serie (36.2 contra 40.7). Aunque el reparto fuera perfecto, lo máximo que se podía ganar era el cálculo, y ese es menos de una quinta parte del frame.

Los dos vuelven a tener sentido si algún día el dibujo deja de ser una escritura por propiedad, que es lo que se explora en [editable-image.md](editable-image.md). Mientras tanto, Spray ya funciona dentro de un Actor sin cambios, en serie.

## Cómo quedó

| Prueba | Spray | Emitter2D |
| --- | --- | --- |
| 1000 partículas en pantalla | 6.4 ms | 8.7 ms |
| 4000 partículas | 25.6 ms | 36.2 ms |
| 1000, color plano y sin giro | 3.6 ms | 6.0 ms |
| 4000, color plano y sin giro | 15.5 ms | 28.4 ms |
| Ráfaga de 200 reutilizando el pool | 1.6 ms | 4.7 ms |
| Ráfagas cada 0.25 s, ~1000 vivas | 8.6 ms | 11.0 ms |

Todo con la misma semilla dando exactamente las mismas partículas que antes, y con los 88 tests pasando. El benchmark está en [bench](https://github.com/mastedore/spray/blob/main/bench/README.md) para volver a correrlo después de cualquier cambio.

Aprendimos que hay que medir la proporción antes de optimizar. Casi todo el tiempo se va en escribirle al motor, así que las mejoras que importaron fueron las que dejaron de hacer trabajo inútil. Hacer más rápidas las cuentas, como con los buffers, apenas movió el total. Probablemente implemente los buffers a futuro honestamente me da pereza.