# Diagnóstico: Ocarina of Time a 10 FPS en Intel Arc B580

Fecha: 2026-11-08 · Build: Fritchii v4.1 (`hotfix/v4.1-f6d42b8715`) · Driver Intel 32.0.101.9150 · i5-12400

## Resultado

La B580 tarda **~101 ms por frame en la propia GPU** (medido con timestamps de GPU,
`EDEN_DKB_FRAME_TRACE=1`). Los hilos del emulador están casi parados esperando a la GPU
(el hilo de back usa ~25 ms de CPU por segundo). No es la CPU ni la sincronización:
`EDEN_NX2_EXP12=1` quita los "full drains" y siguen saliendo 10 FPS.

Casi todo el tiempo se va en ~14 shaders de **cálculo (compute)** por frame, con muy
pocos grupos de trabajo:

| Shader (hash) | GPU por frame | Lanzamientos | Tamaño |
|---|---|---|---|
| `eff3ccbe1438679d` | ~32 ms | 2 | 120×1×1 |
| `e440c9f7923c2973` | ~20 ms | 2 | 60×1×1 |
| `4c1ae2fe58f30a97` | ~17 ms | 1 | 80×180×1 |
| `b20813e55359188f` | ~10 ms | 2 | 720×1×1 |
| `94d8164fdb39f63c` | ~6 ms | 1 | 900×1×1 |
| `97b6662c1e5f549b` | ~6 ms | 1 | 5400×1×1 |
| `f9ea14a22394f5b1` | ~4 ms | 1 | 85×1×1 |

16 ms para 120 grupos de trabajo es anormal: cada grupo corre extremadamente lento.

## Hipótesis (por confirmar)

1. **Matrices cooperativas desactivadas en Arc.** El juego usa HMMA (operaciones de
   matrices). `VK_KHR_cooperative_matrix` se rechaza en la B580 porque el código solo acepta
   formas 16×8×16 / 16×16×16 con grupos de 32 hilos; Intel Xe2 usa 8×16×16 con subgrupos de 16
   (`src/video_core/vulkan_common/vulkan_device.cpp`, bloque `VK_KHR_cooperative_matrix`).
2. **La ruta por software fuerza SIMD32.** Sin matrices cooperativas, HMMA se emula con
   operaciones entre hilos y el pipeline exige subgrupo de 32
   (`src/video_core/renderer_vulkan/vk_compute_pipeline.cpp`). En Intel eso compila SIMD32 y
   puede quedarse sin registros (spills), lo que ya está documentado allí para Mario Kart World.
3. **float16 desactivado en todas las Intel** (workaround antiguo de Astral Chain).

## Confirmado (2026-11-08)

10 de los 11 shaders de cálculo volcados son redes con HMMA (uno con 768, la red de
anti-aliasing de Ocarina). Upstream midió lo mismo en Intel/Mesa (~8 FPS, commit `30097ef6bf`).

## Arreglo en la rama `arc-b580`

- En GPUs Intel sin matrices cooperativas se activa automáticamente el bypass de la red de
  Ocarina (`oot_network.h`, lo mismo que "No sharpening"). `EDEN_ARC_OOT_NETWORK=1` lo desactiva.
- Compilación en Windows con clang-cl 23 + STL de VS 2026: `tools/arc/build.bat`.
- Build de prueba: `G:\Dev\Fritchii-Arc\lichii.exe`.

### Prueba 1 (2026-11-08): sin cambio, sigue a ~100 ms por frame

El bypass se activa, pero las redes lentas **no son** la de anti-aliasing: el volcado no tiene
ninguna de sus claves (`8475d671…`, `42593194…`, `da6df3e5…`), y las mismas ~8 redes corren en cada
frame de la partida.

## Arreglo 2: matrices cooperativas de Intel (8×16×16)

La B580 ofrece estas formas en `VK_KHR_cooperative_matrix` (sondeadas con un programa propio):

| M×N×K | A/B | C/resultado |
|---|---|---|
| 8×16×16 | fp16 | fp32 |
| 8×16×16 | fp16 | **fp16** |
| 8×16×32 | int8 | int32 |

El HMMA del juego es 16×8×16. Su traspuesta es exactamente 8×16×16:
D(16×8) = A·B + C ⇔ Dᵀ(8×16) = Bᵀ·Aᵀ + Cᵀ.

El camino de 16×16×16 ya guarda A, B y C en memoria compartida. Con las mismas baldosas basta con
leerlas en el otro orden:
- Bᵀ se lee de B por filas.
- Aᵀ se lee de A por columnas.
- Cᵀ y Dᵀ se leen y escriben por columnas.

Hay una autoprueba al arrancar (`CooperativeHmmaTestPath::SharedTransposed`) con matrices
conocidas. Si falla, el emulador sigue con la emulación por software. Para comparar, se puede
desactivar con `EDEN_ARC_NO_COOP_MATRIX=1`.

En el registro debe salir:
`Guest tensor operations run transposed on 8x16x16 cooperative matrices`.

## Próximos pasos (originales)

1. Compilar el proyecto (herramientas instaladas en `G:\BuildTools`).
2. Relacionar los hashes de arriba con los shaders volcados en `results_*/shaders`
   (`tools/nx2/shader_sweep.py`) y confirmar si usan HMMA.
3. Añadir un registro por shader de las estadísticas del driver (ancho SIMD, spills).
4. Probar: (a) no forzar subgrupo 32 en Intel donde no haga falta, (b) HMMA con la forma de
   matriz de Intel, (c) reactivar float16 en Arc con drivers recientes.
