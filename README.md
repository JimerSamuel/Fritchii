<!--
# SPDX-FileCopyrightText: Copyright 2025 Eden Emulator Project
# SPDX-License-Identifier: GPL-3.0-or-later

# SPDX-FileCopyrightText: 2018 yuzu Emulator Project
# SPDX-License-Identifier: GPL-2.0-or-later
-->

<h1 align="center">Fritchii · Edición Intel Arc</h1>

<p align="center">
  <b>Emulador experimental de Nintendo Switch / Switch 2 optimizado para GPUs Intel Arc.</b><br>
  De <b>10 FPS a 30 FPS</b> en <i>The Legend of Zelda: Ocarina of Time</i> con una Arc B580.
</p>

<p align="center">
  <img alt="GPU" src="https://img.shields.io/badge/GPU-Intel%20Arc%20B580-0071C5?logo=intel&logoColor=white">
  <img alt="API" src="https://img.shields.io/badge/API-Vulkan%201.4-AC162C?logo=vulkan&logoColor=white">
  <img alt="Compilador" src="https://img.shields.io/badge/compilador-clang--cl%2023-262D3A?logo=llvm&logoColor=white">
  <img alt="Licencia" src="https://img.shields.io/badge/licencia-GPL--3.0-blue">
</p>

> [!NOTE]
> Este es un fork independiente de [Fritchii](https://github.com/Frizti/Fritchii), que a su vez
> viene de Lichii, Eglantine, Eden, yuzu y Sudachi. No es una versión oficial de esos proyectos ni
> está afiliado a Nintendo ni a Intel. Los cambios están en la rama
> [`arc-b580`](https://github.com/JimerSamuel/Fritchii/tree/arc-b580).

---

## ¿Por qué este fork?

Los juegos de Switch 2 usan **redes neuronales** en la GPU (escalado, anti-aliasing, efectos). En la
consola corren sobre los núcleos de matrices de NVIDIA, con una instrucción llamada **HMMA**. Los
emuladores las traducen a la GPU del PC, pero en Intel Arc esa traducción caía en el camino más
lento posible: cada multiplicación de matrices se emulaba **a mano, instrucción por instrucción**.

El resultado en una Arc B580 de 12 GB con el driver más reciente:

```
Ocarina of Time · Arc B580 · driver 101.9150
  antes:   ~100 ms por frame  →  10 FPS   (la GPU ocupada en 8 redes emuladas)
  ahora:   33,4 ms por frame  →  30 FPS   (el límite del propio juego)
```

## Qué cambia

### 1. Las matrices de NVIDIA, ahora sobre las matrices de Intel (XMX)

Las GPUs Arc **sí** tienen unidades de matrices por hardware (XMX), y Vulkan las expone con
`VK_KHR_cooperative_matrix`. El emulador solo aceptaba las formas de NVIDIA y AMD; Intel Xe2 ofrece
otra:

| GPU | Forma que ofrece (M×N×K, fp16) | Antes | Ahora |
|---|---|---|---|
| NVIDIA RTX | 16×8×16 (la del juego) | ✅ matrices | ✅ matrices |
| AMD RDNA3+ | 16×16×16 | ✅ matrices | ✅ matrices |
| **Intel Arc (Xe2)** | **8×16×16** | ❌ emulación lenta | ✅ **matrices** |

La clave es un truco de álgebra: el producto del juego, traspuesto, tiene **exactamente** la forma
de Intel.

```
         D (16×8)  =  A (16×16) · B (16×8)  +  C (16×8)        ← lo que pide el juego

  ⇔     Dᵀ (8×16)  =  Bᵀ (8×16) · Aᵀ (16×16) +  Cᵀ (8×16)       ← lo que sabe hacer Intel
```

```mermaid
flowchart LR
    R["Registros de los 32 hilos<br/>(formato NVIDIA)"] --> S["Memoria compartida<br/>baldosas A, B y C"]
    S -- "B por filas → Bᵀ" --> M["Multiplicación en XMX<br/>8×16×16"]
    S -- "A por columnas → Aᵀ" --> M
    S -- "C por columnas → Cᵀ" --> M
    M -- "Dᵀ por columnas = D" --> S2["Memoria compartida"] --> R2["Cada hilo lee su resultado"]
```

No hace falta copiar ni reordenar datos: basta con **leer las mismas baldosas en otro orden**.

**Seguro por diseño.** Al arrancar, el emulador ejecuta una autoprueba con matrices conocidas y
compara el resultado de cada hilo bit a bit. Si un driver hace algo distinto, se vuelve solo a la
emulación de siempre. En el registro verás una de estas líneas:

```
Guest tensor operations run transposed on 8x16x16 cooperative matrices    ← activo
Cooperative matrix self-test failed (...)                                 ← emulación
```

### 2. Ocarina of Time: anti-aliasing opcional en Intel

En GPUs Intel, la red de anti-aliasing de Ocarina se salta automáticamente, como hace el ajuste
*No sharpening* que ya existía. La imagen queda limpia y sin los halos del enfoque del juego.

### 3. Compila en Windows con las herramientas actuales

- Arreglo para **clang-cl 23** con la STL de **Visual Studio 2026** (MSVC 14.51). Antes fallaba
  un `static_assert` de la STL dentro del traductor de shaders.
- Script de compilación de un solo paso: [`tools/arc/build.bat`](tools/arc/build.bat).

### 4. Herramientas para diagnosticar GPUs Intel

- [`tools/arc/arc_test.ps1`](tools/arc/arc_test.ps1): lanza pruebas A/B con distintas variables de
  depuración y calcula los FPS medios del registro.
- [`tools/arc/DIAGNOSTICO.md`](tools/arc/DIAGNOSTICO.md): el diagnóstico completo, con tiempos de GPU
  por shader, hipótesis descartadas y las formas de matriz que expone la B580.

## Variables de entorno

| Variable | Efecto |
|---|---|
| `EDEN_ARC_NO_COOP_MATRIX=1` | Desactiva las matrices de Intel y vuelve a la emulación (para comparar). |
| `EDEN_ARC_OOT_NETWORK=1` | Mantiene la red de anti-aliasing de Ocarina en Intel. |
| `EDEN_DKB_FRAME_TRACE=1` | Tiempos de GPU por shader en el registro. |
| `EDEN_NX2_SHADER_DUMP=<carpeta>` | Vuelca los shaders del juego para analizarlos. |

## Uso

1. Descarga la build (o compílala, ver abajo) y extrae **toda** la carpeta.
2. Ejecuta `lichii.exe`. Usa los mismos datos que Fritchii/Lichii
   (`%APPDATA%\eden`), así que tus juegos, partidas y ajustes ya estarán ahí.
3. Usa solo juegos, claves y firmware que hayas obtenido legalmente. No se incluyen.

Para probar desde PowerShell:

```powershell
& "C:\ruta\a\lichii.exe"
```

## Compilar en Windows

Necesitas Visual Studio 2026 (C++), LLVM 23 (clang-cl), CMake, Ninja y el Vulkan SDK.
Ajusta las rutas al principio de [`tools/arc/build.bat`](tools/arc/build.bat) y ejecuta:

```bat
tools\arc\build.bat
```

El ejecutable queda en `build\release\bin\lichii.exe`. La guía general está en
[docs/Build.md](docs/Build.md).

## Hoja de ruta

- [x] Diagnóstico: el cuello de botella es la GPU, en las redes HMMA emuladas.
- [x] HMMA sobre las matrices XMX de Intel (8×16×16, traspuesto).
- [x] Autoprueba al arrancar con vuelta atrás automática.
- [ ] Probar más juegos de Switch 2 con redes (Donkey Kong Bananza, Kirby Air Riders…).
- [ ] Usar subgrupos de 16 hilos, el tamaño natural de Intel, en lugar de forzar 32.
- [ ] Sustituir el DLSS de los juegos por **XeSS** en Intel, igual que ya se hace con FSR 3.1.
- [ ] Llevar estos cambios a Fritchii y Eglantine para que lleguen a todos.

## Reportar problemas

Abre un [issue](https://github.com/JimerSamuel/Fritchii/issues) con:

- Build, versión del juego, CPU, GPU y versión del driver.
- Pasos para reproducirlo y una captura.
- El registro `%APPDATA%\eden\log\eden_log.txt` de esa sesión (revísalo antes por si tiene datos
  personales).

No subas juegos, claves, firmware ni datos de tu cuenta.

## English summary

An Intel Arc–focused fork of Fritchii. Switch 2 games run neural networks through NVIDIA's HMMA
tensor instruction, which used to fall back to slow shader emulation on Arc because Xe2 only
exposes **8×16×16** cooperative matrices. This fork runs the guest's 16×8×16 product as its
transpose (Dᵀ = Bᵀ·Aᵀ + Cᵀ) on Intel's XMX units through the existing shared-memory tiles, guarded
by a startup self-test. Result on an Arc B580: Ocarina of Time goes from **~100 ms to 33 ms per
frame (10 → 30 FPS, the game's cap)**. It also builds with clang-cl 23 + MSVC 14.51 and adds Arc
diagnostic tools.

## Créditos y licencia

Este fork hereda el trabajo de **Fritchii** (Frizti), **Lichii** (zortos293), **Eglantine** (Camille
LaVey y colaboradores), **Eden**, **yuzu** y **Sudachi**. Se conservan todos los avisos de copyright y
las licencias de terceros. Si quieres apoyar el desarrollo, apoya también a esos proyectos.

Arte de Lichii creado por YOB (yobslab), en [dist/branding](dist/branding).

Licencia: [GPL-3.0](LICENSE.txt). Consulta los archivos fuente para los términos aplicables.
