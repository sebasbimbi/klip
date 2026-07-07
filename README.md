<div align="center">

# 📋 Klip

**El gestor de copiado para vibe coders.**
Todo lo que copias mientras construyes con IA — código, errores, capturas, prompts y llaves — a un atajo de distancia.

Historial de texto e imágenes · **captura nativa + anotación** · **OCR rápido** · **notas de voz y video → texto** (en el equipo, u OpenAI/Gemini) · **copiar como bloque de código / para WhatsApp / para correo** · **pegado siempre limpio** · **credenciales cifradas**. Vive en la barra de menús: ligero, rápido y privado.

🆓 Gratis y open source (MIT) · 🔒 Sin telemetría · 🍎 Swift nativo (sin Electron)

<br/>

<img src="docs/klip-preview.gif" alt="Klip en acción: recorta un área de la pantalla, aparece en Klip y extrae su texto con OCR; y graba una nota de voz que se transcribe sola" width="500"/>

<sub>Recorta un área → cae en Klip → extrae el texto (OCR) · y graba una nota de voz que se transcribe sola.</sub>

</div>

> ### 🖥️ Por ahora, solo Mac
> Klip es una app **nativa de macOS** y requiere **macOS 14 (Sonoma) o posterior** (Apple Silicon o Intel).
> La **versión para Windows 🪟 saldrá próximamente**. Tus datos se quedan en tu equipo.

---

## 🤔 ¿Por qué Klip si programas con IA?

El "vibe coding" es un ida y vuelta constante de copiar y pegar entre tu editor y herramientas como Claude, ChatGPT o Cursor: fragmentos de código, mensajes de error, capturas de UI, salida de terminal, prompts dictados y llaves de API. Klip está hecho para ese flujo:

- **No pierdas ningún fragmento** — todo lo que copias cae en un historial con buscador.
- **Recorta un error y anótalo** (flechas, texto, resaltador) sin soltar el teclado; queda en Klip listo para pegarlo en la IA.
- **Extrae el texto de una captura** (OCR) para pegar un log que quedó atrapado en una imagen.
- **Copia como bloque de código** (` ``` `) para pegar limpio en un chat.
- **Dicta un prompt** — o **suelta un audio o un video** — y Klip lo transcribe a texto.
- **Agrupa varios clips** (capturas + textos) en un **PDF o ZIP** para subir el contexto completo de una sola vez.
- **Tus llaves de API** quedan detectadas, **cifradas en reposo**, con nombre y buscables.

## ✨ Funciones

### 📋 Portapapeles
- **Historial automático** de **texto e imágenes/capturas**.
- **Búsqueda instantánea** con **resaltado de coincidencias** + **navegación por teclado** (↑/↓, Enter, `⌘↩` copiar-como-código, `Esc`).
- **Filtros por tipo** (texto · **links** · imágenes · voz · credenciales · favoritos); el chip de un tipo solo aparece cuando ya tienes elementos de ese tipo.
- **Auto-pegado** en la app activa · **Favorito** ⭐ · **Renombrar** ✏️ · **Eliminar** 🗑️ (con confirmación al vaciar todo).
- **Fecha legible** en cada elemento: *"mar, 04 jul · 10:43"*, *"Hoy"*, *"Ayer"*.

### 📸 Captura nativa + anotación (Klip Snap)
- Atajo global **`⌥⇧D`** → recorta una región de la pantalla (arrastra una selección sobre un *freeze-frame* atenuado, con medidas en vivo y escala Retina correcta). Usa **ScreenCaptureKit** (no la API obsoleta).
- **Editor de anotaciones** integrado: lápiz, línea, **flecha**, rectángulo, elipse, resaltador, **texto editable/movible/redimensionable**, color, grosor y **deshacer**.
- Al terminar, la captura anotada cae en el **historial** (lista para **OCR** y búsqueda) y en el portapapeles.
- También desde el botón 📷 del panel o el menú de la barra.
- **Captura rápida de texto** (`⌥⇧F`): recorta una región y su **texto pasa por OCR directo al portapapeles** (y al historial) — se salta el editor cuando solo necesitas el texto.

### 🎙️ Notas de voz y video → texto
- **Graba** (`⌥⇧R`) o **sube archivos** (`⌥⇧O`): audio (m4a, mp3, wav, **.opus de WhatsApp**, ogg, flac…) **y también video** (mp4, mov, mkv, webm…) — Klip **extrae la pista de audio del video** y la transcribe.
- Transcribe **en segundo plano** — puedes grabar otra nota de inmediato. Si subes **un solo archivo**, la transcripción **queda copiada al portapapeles automáticamente**.
- **El audio original se conserva** con **duración** y **barra de progreso**: reprodúcelo (▶) o muéstralo en Finder, y **reintenta (↻)** si una transcripción falla. (El video no se guarda — solo su texto.)
- **Idioma por archivo** al subir (p. ej. un audio en francés aunque la app esté en español).
- Errores claros por archivo: video protegido (DRM), sin pista de audio, demasiado grande para la nube.

### 🤖 IA: tú eliges el motor
- **En el equipo (por defecto)** — transcribe **totalmente offline con Whisper** ([WhisperKit](https://github.com/argmaxinc/WhisperKit) sobre Core ML): **sin llave de API y sin que el audio salga de tu Mac.** Elige el modelo (Tiny / Base / Small / Large v3 Turbo); se descarga una vez y luego funciona sin conexión.
- **OpenAI** o **Google Gemini** — motores en la nube opcionales; usa tu propia llave. En **Gemini** puedes elegir el modelo (`gemini-flash-latest`, `-flash-lite-latest`, `-pro-latest`, `2.5-flash`, `2.5-pro`); en **OpenAI**, `gpt-4o-mini-transcribe` o `whisper-1`.
- **Idioma de dictado** seleccionable (y autodetección), para una transcripción natural en tu idioma.
- **Palabras de contexto** — lista nombres, marcas o jerga (p. ej. `GitHub, React, Supabase, API, webhook`) para que el transcriptor escriba bien tus nombres propios. También funciona con el motor local.

### 🖼️ Imágenes
- Vista previa grande (miniaturas cacheadas para un scroll fluido), **abrir en grande** y **guardar a archivo**.
- **OCR** (extraer el texto de una imagen) con **Vision** de Apple — gratis y en el equipo. Perfecto para sacar el texto de un log o error que copiaste como captura.

### 🧰 Hecho para pegar en la IA
- **Copiar como bloque de código** — envuelve el texto en ` ``` ` (con etiqueta de lenguaje detectada) para pegarlo limpio en un chat (`⌘↩` sobre el elemento seleccionado).
- **Copiar para WhatsApp / para correo** — reformatea un clip para que pegue bien: marcado de WhatsApp (`*negrita*`, `_cursiva_`, • viñetas) o texto enriquecido de correo (renderiza negrita/cursiva y conserva el espaciado).
- **Pegado siempre limpio** (activado por defecto) — lo copiado desde una fuente con formato (p. ej. un chat de IA en tema oscuro) se guarda como texto limpio que conserva **negrita/cursiva + emojis** pero descarta el fondo oscuro, los colores y las fuentes.
- **Copiar como Markdown** un elemento, o exportar **todo el historial** a Markdown.
- **Guardar un texto como archivo** (`.txt`/`.md`) para arrastrarlo a una herramienta cuando el chat no deja pegarlo.
- **Multiselección** (icono ☑️ en la cabecera): marca varios clips y…
  - **Combínalos en un PDF** (una página por captura/texto) para subir el contexto completo de una vez.
  - **Expórtalos como ZIP** (el subconjunto elegido, aparte del ZIP de respaldo).
  - **Asígnalos a una colección**.

### 🏷️ Organización
- **Colecciones** — agrupa clips relacionados (p. ej. el contexto de una tarea) y fíltralos con un chip.
- **Renombra cualquier elemento** y encuéntralo por ese nombre (ideal para tus credenciales: "Llave prod", "Script de deploy").
- **Acciones según el tipo**: **abrir links** 🔗 y **muestra de color** para valores hex (`#1E90FF`).
- **Mini gestor de credenciales** 🔑: detecta tokens y llaves de API al copiarlas y las **cifra en reposo** (AES-256-GCM, llave en el Llavero de macOS — así ni `items.json` ni los respaldos guardan el secreto en claro). Se muestran **enmascaradas** (👁 para revelar/copiar), con su propio filtro, y **nunca se auto-pegan** (se copian para que las pegues tú).

### 💾 Respaldo
- **Exporta / importa** el historial completo (imágenes y audio incluidos) como `.zip`. **Nunca** incluye tus llaves de API.

### 🌍 Idiomas
- Interfaz disponible en **español, inglés, francés, alemán, italiano, portugués, chino (simplificado) y japonés**, cambiable en Preferencias.

### 🔒 Privacidad y sistema
- Todo **local** con permisos `0600` · **sin telemetría** · ignora contraseñas y permite **excluir apps**.
- **Firma estable**: macOS pide los permisos (micrófono, grabación de pantalla…) **una sola vez** y los recuerda entre actualizaciones.
- **Abrir al iniciar sesión** opcional.

## ⌨️ Atajos

Los atajos globales usan **⌥⇧ (Opción+Shift)** + una letra, agrupados por función en el lado izquierdo del teclado — cómodos de mantener y rara vez ocupados por otras apps (así el atajo global sí dispara; `⌘⇧`+letra choca con VS Code / navegadores):

| Atajo | Acción |
|---|---|
| `⌥⇧E` | Abrir el panel de historial |
| `⌥⇧R` | G**r**abar / detener una nota de voz |
| `⌥⇧D` | Capturar una región y anotarla (**d**ibujar — Klip Snap) |
| `⌥⇧F` | Captura rápida de texto: recorta una región → OCR directo al portapapeles, sin editor |
| `⌥⇧O` | Abrir la ventana de "subir audio/video a transcribir" |
| `↑` / `↓` · `Enter` | Navegar y elegir un elemento |
| `⌘↩` | Copiar el elemento seleccionado como bloque de código (``` ```) |
| `Esc` | Cerrar el panel |
| `⌘⇧⌃4` | *(macOS)* captura al portapapeles → también cae en Klip |

> Los cinco atajos globales son **configurables** en Preferencias › Atajos.

## 🧰 Requisitos

- **macOS 14 (Sonoma) o posterior** — probado en macOS 26; funciona en **Intel y Apple Silicon**.
- **Xcode Command Line Tools** (no hace falta Xcode completo):
  ```bash
  xcode-select --install
  ```
- *(Opcional)* Una **llave de API de OpenAI o Google Gemini** para transcripción en la nube. Se guarda en un **archivo local**, nunca en el código ni en el repositorio.

## ⚡ Instalación rápida

```bash
git clone https://github.com/tamibot/klip.git klip
cd klip
./install.sh
```

Eso compila Klip, lo firma, lo copia a `/Applications`, lo abre y registra el arranque al iniciar sesión.
Verás el icono 📋 en la barra de menús. Pulsa **`⌥⇧E`** para abrir el historial.

> En el primer uso, `install.sh` crea un **certificado de firma local** (`Klip Code Signing`) en tu Llavero para que la firma sea estable. Así macOS pide los permisos (micrófono, accesibilidad, grabación de pantalla) **una sola vez** y los recuerda entre actualizaciones, en lugar de volver a pedirlos en cada reinstalación. Es local y reversible (puedes borrarlo desde *Acceso a Llaveros*).
>
> macOS puede pedirte aprobar el "ítem de inicio" en *Configuración › General*. Para el **auto-pegado**, concede Accesibilidad cuando lo pida (menú de Klip → *Activar auto-pegado…*). La primera captura con `⌥⇧D` pedirá **Grabación de pantalla**.

### Compilar sin instalar

```bash
./build.sh        # genera Klip.app en la carpeta del proyecto
open Klip.app
```

### Desarrollo

```bash
swift build       # compilación de depuración
swift run Klip    # ejecutar directamente
```

## 🚀 Uso (el flujo típico de un vibe coder)

1. **Copia lo que sea** mientras programas (código, salida de terminal, un mensaje de error). Todo cae en Klip.
2. **`⌥⇧E`** → abre el panel. Escribe para **buscar**; usa **↑/↓ + Enter** o **clic** para elegir un elemento (se auto-pega si activaste el auto-pegado).
3. Para pegar código en un chat de IA, pasa el cursor por la fila y pulsa **`</>`** (*copiar como bloque de código*).
4. **`⌥⇧D`** → recorta el error/la UI, anótalo (flecha + texto) y cae en Klip. O **`⌥⇧F`** para recortar una región y obtener su **texto por OCR directo al portapapeles** (sin editor).
5. 🎙️ **`⌥⇧R`** para dictar un prompt; al parar, se transcribe y cae en el historial. O **`⌥⇧O`** y suelta un **audio o video** — si es uno solo, el texto queda copiado automáticamente.
6. ☑️ Activa la **multiselección** en la cabecera, marca varias capturas/textos y pulsa **PDF** o **ZIP** para subirlos como contexto a la IA de una sola vez.
7. `Esc` o un clic fuera cierra el panel.

## ⚙️ Configuración

Abre **Preferencias** (`⌘,` desde el menú de Klip):

- **Atajos** — graba las combinaciones que prefieras (historial, voz, anotar, OCR rápido, subir). Por defecto: `⌥⇧E / R / D / F / O`.
- **Transcripción de voz** — elige el **motor** (en el equipo, OpenAI o Google Gemini), el **modelo**, el idioma y las **palabras de contexto**.
- **OpenAI / Google Gemini** — pega la llave de API del motor que elegiste (solo se muestra esa sección). Se guarda en un archivo local `0600`.
- **Historial** — número máximo de elementos.
- **Privacidad** — ignorar contraseñas/contenido sensible, excluir apps, interruptor de **pegado siempre limpio**.
- **Idioma** — idioma de la interfaz.

## 🔐 Privacidad

- **Local primero**: tu historial vive en `~/Library/Application Support/Klip/` (`items.json` + `images/` + `audio/`). Nada sale de tu Mac salvo el audio que **tú** envías al motor de IA que elijas (OpenAI o Gemini) para transcribir.
- **Sin secretos en el repo**: las llaves de API se guardan en **archivos locales** (`openai.key`, `gemini.key`, permisos `0600`), nunca en el código ni en el repositorio.
- El **historial** (`items.json`), las **imágenes** y el **audio** de las notas de voz se guardan solo en tu Mac con permisos `0600` (carpetas `0700`). Las credenciales van además **cifradas en reposo** (AES-256-GCM; la llave vive en el Llavero de macOS), así el secreto nunca queda en claro en `items.json` ni en los respaldos.
- **Sin telemetría**.
- Klip **ignora** el contenido que los gestores de contraseñas marcan como oculto, y puedes **excluir** apps concretas.
- Los **tokens/llaves de API** que copias se detectan, se **cifran en reposo** y se muestran **enmascarados** (filtro 🔑).

## 🏗️ Arquitectura

| Archivo | Responsabilidad |
|---|---|
| `main.swift` / `AppDelegate.swift` | Arranque, barra de menús, menú Edición, atajos globales. |
| `ClipboardManager.swift` | Monitoreo del portapapeles, historial, privacidad, colecciones. |
| `ClipboardItem.swift` / `Storage.swift` | Modelo y persistencia (JSON + imágenes + audio + PDF/ZIP). |
| `PanelController.swift` / `HistoryView.swift` | Panel HUD y la UI (SwiftUI), multiselección y exportación. |
| `SnapController.swift` / `ScreenCapturer.swift` | Flujo de captura nativa (ScreenCaptureKit), incl. modo **OCR directo** (`⌥⇧F`). |
| `CaptureOverlayController.swift` | Overlay de selección de región (freeze-frame + medidas). |
| `SnapEditorController.swift` / `AnnotationCanvasView.swift` / `AnnotationModel.swift` | Editor de anotaciones y su modelo. |
| `HotKey.swift` / `Settings.swift` | Atajos (Carbon) y preferencias (UserDefaults). |
| `OCR.swift` | Extracción de texto con Vision (en el equipo). |
| `CredentialCrypto.swift` / `CredentialDetector.swift` | Detección de credenciales + **cifrado en reposo AES-256-GCM** (llave en el Llavero). |
| `RichText.swift` | Texto enriquecido del portapapeles → Markdown limpio (conserva negrita/cursiva + emojis) para el *pegado siempre limpio*. |
| `UploadView.swift` | Ventana de "subir audio/video a transcribir" con resultados en vivo por archivo. |
| `Recorder.swift` / `AudioPlayer.swift` | Grabación, transcripción en segundo plano y reproducción de notas de voz. |
| `MediaAudioExtractor.swift` | Extrae la pista de audio de un **video** (AVAssetReader→Writer, 16 kHz mono AAC) para transcribirla. |
| `OpenAIClient.swift` / `GeminiClient.swift` / `LocalTranscriber.swift` | Transcripción vía OpenAI, Google Gemini o WhisperKit local. |
| `L10n.swift` | Localización ligera (8 idiomas). |
| `SecretStore.swift` | Llaves de API en archivos locales `0600` (`openai.key`, `gemini.key`). |
| `Paster.swift` / `LoginItem.swift` | Auto-pegado y arranque al iniciar sesión. |
| `Markdownify.swift` | Conversión y exportación a Markdown (local). |

## 🗺️ Hoja de ruta

**Klip es solo para Mac por ahora.** Lo que viene:

- [ ] **Versión para Windows** 🪟 — el gran siguiente paso.
- [ ] Más acciones rápidas según el tipo (correos, números).
- [ ] Traducir / resumir / limpiar texto con IA.
- [ ] Favoritos sincronizados · sincronización opcional entre Macs.
- [ ] Firma Developer ID + notarización para distribuir sin avisos.

**Ya disponible:** historial de texto+imágenes · captura nativa + anotación (Klip Snap) · **OCR rápido** (`⌥⇧F`) · OCR · notas de voz **en el equipo** (WhisperKit) además de OpenAI/Gemini, **subir audio y video** con idioma por archivo, audio conservado y reintento · copiar como bloque de código / **para WhatsApp / para correo** · **pegado siempre limpio** · **credenciales cifradas (AES-256-GCM)** · filtro de **links** · multiselección + combinar en PDF/ZIP · colecciones · renombrar y buscar · muestra de color · Markdown · exportar/importar · firma estable · 8 idiomas de interfaz.

## 🤝 Contribuir

¡Las contribuciones son bienvenidas! Abre un *issue* o un *pull request*. El proyecto compila solo con las Command Line Tools (sin Xcode), así que es fácil empezar. La documentación y los comentarios del código están en español.

## 👤 Autor

Creado y mantenido por **Martin Velasco O.** — [@tamibot](https://github.com/tamibot).

## 📄 Licencia

[MIT](LICENSE) © 2026 Martin Velasco O. — úsalo, modifícalo y compártelo libremente.
