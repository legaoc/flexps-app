# iPlayerPod — versión 100% nativa en Swift (SwiftUI)

Reescritura nativa del reproductor local "iPlayerPod" (antes un solo
`index.html` de 6,000 líneas, v1.6.2, en `legaoc/flexps`). Mismo contenido
y funciones que la web, con interfaz nativa de Apple, sin copiar el estilo
web. App 100% local: sin cuenta, sin login, sin Firebase, sin servidores
propios.

La versión web (`legaoc/flexps`) sigue como respaldo hasta que esta versión
Swift esté completa y probada.

## Estructura

```
Flexps/                   Proyecto Xcode (SwiftUI, iOS 17+)
  Flexps.xcodeproj/       project.pbxproj (sin dependencias externas)
  Flexps/
    FlexpsApp.swift       Arranque, @StateObject de Store y Player
    ContentView.swift     TabView: Inicio / Playlists / Buscar / Favoritos + mini player
    Models.swift          Song, Playlist, LibraryMeta, LyricsCacheEntry, SortMode, YouTubeTrack
    LibraryStore.swift    JSON en Documents/library.json + archivos en Documents/Music y Covers
    PlayerManager.swift   AVPlayer + segundo AVPlayer para crossfade, Now Playing, sleep timer
    MetadataService.swift AVAsset (tags/duración) + Deezer con el scoring de la web
    LyricsService.swift   LRCLib + parser LRC
    YouTubeService.swift  Búsqueda YouTube Data API v3 (con tu clave) + oEmbed sin clave
    YouTubePlayerView.swift WKWebView con IFrame Player API oficial
    HomeView.swift        Inicio: YouTube, playlists y álbumes recientes, explorar
    LibraryViews.swift    Canciones, artistas, álbumes, detalles y Favoritos
    SearchView.swift      Búsqueda global + vista de YouTube
    PlaylistsView.swift   Playlists CRUD y detalle
    ForYouView.swift      Para ti: más reproducidas, favoritas de la semana, recientes
    PlayerViews.swift     Mini player, full player, karaoke, cola
    SettingsView.swift    Tema, crossfade, sleep timer, clave YouTube, almacenamiento
    Theme.swift           Tema claro/oscuro/sistema y formato
    VersionHistory.swift  Historial de versiones
    Info.plist            Audio en segundo plano (UIBackgroundModes: audio)
    Assets.xcassets/      Icono (nota musical blanca sobre negro) + color de acento
.github/workflows/build-ipa.yml  Compila el IPA sin firma en GitHub Actions
WEB-INVENTORY.md          Inventario real de la web con fuentes (líneas de index.html y api/*.js)
CHANGELOG.md              Historial de versiones Swift
```

## Datos

- Biblioteca local: `Documents/library.json` (metadatos, playlists, meta,
  letras) + `Documents/Music/<id>.<ext>` (audio copiado al importar) +
  `Documents/Covers/` (portadas embebidas o de Deezer).
- La clave de YouTube Data API v3 se guarda en UserDefaults
  (`flexps.youtubeApiKey`), solo en el teléfono, nunca en el repo.
- Deezer y LRCLib se llaman directo con URLSession, sin clave.
- YouTube se reproduce con el IFrame Player oficial en WKWebView; el audio
  no se extrae.

## Instalación del IPA

El IPA se compila SIN firma (`CODE_SIGNING_ALLOWED=NO`): no se instala
directo en iPhone. Hay que firmarlo con AltStore o Sideloadly con un
Apple ID propio.

## Estado (1.0)

Hecho: importar MP3/M4A/WAV/AAC/FLAC/MP4 con tags y portada embebida;
canciones, artistas, álbumes y detalles; búsqueda global; los 7 órdenes
de la web; playlists CRUD; favoritos de canciones/playlists/álbumes/
artistas; recientes; Para ti; reproductor con cola, aleatorio, repetir,
crossfade 1–12 s, temporizador de apagado, karaoke con letra sincronizada;
letras LRCLib con caché; info Deezer; YouTube (buscar con clave, pegar
enlace sin clave); tema claro/oscuro; almacenamiento y borrar biblioteca.

Pendiente (anotado, no inventado): visualizador de audio por analyser
(la web lo tenía con Web Audio API; en Swift sería AVAudioEngine con un
tap, no se incluyó en 1.0).
