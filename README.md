<div align="center">

# 📋 Klip

**Tu portapapeles con superpoderes.** Todo lo que copias, a un atajo de distancia.

Historial de texto e imágenes · búsqueda instantánea · **notas de voz → texto** · **OCR** · Markdown · y más. Vive en la barra de menú, es ligero y privado.

🖥️ **macOS 14+** · 🪟 *Windows — próximamente* · 🆓 Gratis y open source · 🔒 Sin telemetría

*Hecho en Swift nativo. Sin Electron. Tus datos se quedan en tu equipo.*

</div>

---

## ✨ Funciones

- 📋 **Historial automático** de texto **e imágenes/capturas** que copias.
- ⌨️ **Atajo global `⌘⇧E`** (Cmd+Shift+E) para abrir el panel desde cualquier app. Configurable.
- 🔎 **Búsqueda** instantánea **con resaltado** de coincidencias y **navegación por teclado** (↑/↓, Enter, `⌘1`–`⌘9`, `Esc`). Filtros por tipo (texto, imágenes, voz, credenciales, fijados).
- ⤵️ **Pegado automático**: eliges un elemento y se pega solo en la app activa.
- 🖼️ **Imágenes**: previsualización grande (con miniaturas en caché para que vaya fluido), **abrir en grande**, **guardar como archivo** y **extraer texto (OCR)** con el motor Vision de Apple (gratis, en el dispositivo).
- 🎙️ **Notas de voz → texto**: grabas, paras, y se transcribe la nota completa **en segundo plano** (puedes grabar otra al instante). **El audio original se guarda** con su **duración y barra de progreso**, lo **reproduces desde Klip** (▶) o lo abres en Finder, y puedes **reintentar (↻)** si la transcripción falla — así no pierdes nada. También puedes **subir un archivo** (m4a, mp3, wav, **.opus de WhatsApp**, ogg, flac…).
- 🤖 **Elige tu motor de IA**: **OpenAI** o **Google Gemini** para la transcripción. Pones tu propia clave de cualquiera de los dos.
- 🏷️ **Ponle nombre a todo**: etiqueta cualquier elemento (texto, imagen, voz o credencial) y **búscalo por ese nombre**. Ideal para tus credenciales: les pones un nombre y las encuentras al instante.
- 🔗 **Acciones por tipo**: **abrir enlaces** (URLs), **muestra de color** para valores hex (`#1E90FF`).
- 📝 **Markdown**: copia cualquier elemento *como Markdown* o exporta **todo el historial** a Markdown.
- 🔑 **Mini gestor de credenciales**: detecta tokens y API keys al copiarlos, los guarda **aparte y enmascarados** (👁 para revelar/copiar), con su propio filtro 🔑.
- 📌 **Fijar**, 🗑️ **eliminar** (con confirmación al **borrar todo**), y **hora exacta** de copiado en cada elemento.
- 🔒 **Privacidad**: ignora contraseñas (contenido marcado como oculto), permite **excluir apps**, y guarda todo **localmente** con permisos `0600`.
- 🔏 **Firma estable**: macOS te pide los permisos (micrófono…) **una sola vez** y los recuerda entre actualizaciones.
- 🚀 **Arranque al iniciar sesión** opcional · 🌍 **Español / Inglés**.

## 🧰 Requisitos

- **macOS 14 (Sonoma) o superior** — probado en macOS 26, Apple Silicon.
- **Command Line Tools de Xcode** (no hace falta Xcode completo):
  ```bash
  xcode-select --install
  ```
- *(Opcional)* Una **API key de OpenAI** para las notas de voz y el Markdown por IA. Se guarda en un **archivo local** de la app, nunca en el código ni en el repositorio.

## ⚡ Instalación rápida

```bash
git clone <URL-de-tu-repositorio> klip
cd klip
./install.sh
```

Eso compila Klip, lo firma, lo copia a `/Applications`, lo lanza y registra el arranque al inicio.
Verás el icono 📋 en la barra de menú. Pulsa **`⌘⇧E`** para abrir el historial.

> La primera vez, `install.sh` crea un **certificado de firma local** (`Klip Code Signing`) en tu Llavero para que la firma sea estable. Así macOS te pide los permisos (micrófono, accesibilidad) **una sola vez** y los recuerda entre actualizaciones, en lugar de volver a preguntar en cada reinstalación. Es local y reversible (puedes borrarlo desde *Acceso a Llaveros*).
>
> macOS puede pedir aprobar el "ítem de inicio de sesión" en *Ajustes › General*. Para el **pegado automático**, concede Accesibilidad cuando se solicite (menú de Klip → *Activar pegado automático…*).

### Compilar sin instalar

```bash
./build.sh        # genera Klip.app en la carpeta del proyecto
open Klip.app
```

### Desarrollo

```bash
swift build       # compilación de depuración
swift run Klip    # ejecuta directamente
```

## 🚀 Uso

1. Copia lo que sea (texto, o una captura con `⌘⇧⌃4`, que va al portapapeles).
2. Pulsa **`⌘⇧E`** → se abre el panel.
3. Escribe para **buscar**; usa **↑/↓ + Enter** o haz **clic** para elegir un elemento (se pega solo si activaste el pegado automático).
4. Pasa el cursor sobre una fila para ver acciones: copiar, guardar imagen, **OCR**, **Markdown**, fijar, eliminar.
5. 🎙️ Pulsa el **micrófono** para grabar una nota de voz; al detener, se transcribe y entra al historial.
6. 📝 Botón **Markdown** del encabezado: copia **todo** el historial como Markdown.
7. `Esc` o clic fuera cierra el panel.

## ⚙️ Configuración

Abre **Preferencias** (`⌘,` desde el menú de Klip):

- **Atajos** — graba las combinaciones que prefieras (panel y voz).
- **Transcripción de voz** — elige **proveedor** (OpenAI o Google Gemini), modelo e idioma.
- **OpenAI** — pega tu API key (`sk-…`). Se guarda en un archivo local `0600`.
- **Google Gemini** — pega tu API key (`AIza…`, de [aistudio.google.com](https://aistudio.google.com)). Se guarda en un archivo local `0600`.
- **Historial** — número máximo de elementos.
- **Privacidad** — ignorar contraseñas/contenido sensible, excluir apps.

## 🔐 Privacidad

- **Local primero**: tu historial vive en `~/Library/Application Support/Klip/` (`items.json` + `images/` + `audio/`). Nada sale de tu Mac salvo el audio que **tú** envías al proveedor de IA que elijas (OpenAI o Gemini) para transcribir.
- **Sin secretos en el repo**: las API keys se guardan en **archivos locales** (`openai.key`, `gemini.key`, permisos `0600`), jamás en el código ni en el repositorio.
- El **historial** (`items.json`), las **imágenes** y el **audio** de las notas de voz se guardan solo en tu Mac con permisos `0600` (carpetas `0700`). El enmascarado de credenciales es visual; el contenido vive localmente como el resto del historial.
- **Sin telemetría**.
- Klip **ignora** el contenido marcado como oculto por los gestores de contraseñas, y puedes **excluir** apps concretas.
- Los **tokens/API keys** que copies se detectan y se guardan **enmascarados** (filtro 🔑).

## 🏗️ Arquitectura

| Archivo | Responsabilidad |
|---|---|
| `main.swift` / `AppDelegate.swift` | Arranque, barra de menú, atajo global. |
| `ClipboardManager.swift` | Monitoreo del portapapeles, historial, origen, privacidad. |
| `ClipboardItem.swift` / `Storage.swift` | Modelo y persistencia (JSON + imágenes + audio). |
| `PanelController.swift` / `HistoryView.swift` | Panel HUD y la interfaz (SwiftUI). |
| `HotKey.swift` / `Settings.swift` | Atajo (Carbon) y preferencias (UserDefaults). |
| `OCR.swift` | Extracción de texto con Vision. |
| `Recorder.swift` / `AudioPlayer.swift` | Grabación, transcripción en 2º plano y reproducción de notas de voz. |
| `OpenAIClient.swift` / `GeminiClient.swift` | Transcripción vía OpenAI o Google Gemini (proveedor seleccionable). |
| `SecretStore.swift` | API keys en archivos locales `0600` (`openai.key`, `gemini.key`). |
| `Paster.swift` / `LoginItem.swift` | Auto-pegado y arranque al inicio. |
| `Markdownify.swift` | Conversión y exportación a Markdown (local). |

## 🗺️ Hoja de ruta

- [ ] **Versión para Windows** 🪟 (próximamente).
- [ ] Traducir / resumir / limpiar texto con IA.
- [ ] Colecciones / favoritos.
- [ ] Sincronización opcional entre Macs.
- [ ] Acciones rápidas por tipo (enlaces, colores, código).
- [ ] Firma con Developer ID + notarización para distribución sin avisos.

## 🤝 Contribuir

¡Las contribuciones son bienvenidas! Abre un *issue* o un *pull request*. El proyecto compila solo con las Command Line Tools (sin Xcode), así que es fácil de arrancar.

## 👤 Autor

Creado y dirigido por **Martin Velasco O.** — [@tamibot](https://github.com/tamibot) · Proper.

## 📄 Licencia

[MIT](LICENSE) © 2026 Martin Velasco O. — úsalo, modifícalo y compártelo libremente.
