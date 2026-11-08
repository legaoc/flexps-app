# Inventario real de la web iPlayerPod (v1.6.2) → Swift 1.0

Fuente: `~/workspace/flexps/index.html` (6,000 líneas, un solo archivo),
`~/workspace/flexps/api/youtube-search.js` (53 líneas),
`~/workspace/flexps/api/music-info.js` (385 líneas).
Repo original: `legaoc/flexps` (no tocado).

## Identidad

| Dato | Web | Swift 1.0 |
|---|---|---|
| Nombre visible | iPlayerPod | iPlayerPod |
| Versión | `APP_VERSION = "1.6.2"` (index.html:1568) | 1.0 (propia; la web sigue en 1.6.2) |
| Bundle ID | — (web) | com.legaoc.flexps |
| Persistencia | IndexedDB `MusiquitaDB` v5 (index.html:1654-1655) | `Documents/library.json` + `Documents/Music/` + `Documents/Covers/` |

## Almacenamiento web → Swift

- Stores IndexedDB (index.html:1656-1660, 1878-1887): `songs`, `playlists`,
  `meta`, `lyrics` → `LibraryData` en `library.json` (mismos 4 grupos).
- Canción: `id` UUID, `name`, `type`, `size`, `addedAt`, `duration`,
  `title`, `artist`, `album`, `cover`, `albumCover`, `artistImage`,
  `releaseDate`, `infoSource`, `favorite`, `favoritedAt`, `playCount`
  → `Song` en `Models.swift` (mismos campos; `coverFileName` extra para
  la portada guardada como archivo).
- Meta (index.html:1972): `theme`, `queue`, `recentPlaylists`,
  `recentAlbums`, `favoritePlaylists`, `favoriteAlbums`, `favoriteArtists`,
  `crossfadeOn`, `crossfadeSeconds` → `LibraryMeta` (mismos campos).
- Import: picker múltiple `.mp3/.mp4/.m4a/.wav/.aac/.flac`
  (index.html:2460), duración y tags con jsmediatags
  (`readDuration` 2015, `readTags` 2051), Blob en IndexedDB
  → `LibraryStore.importFiles` con `fileImporter` + `AVAsset`
  (commonMetadata + duration), copia a `Documents/Music/<id>.<ext>`.
- `cleanFileName` / `guessTrackInfo` (index.html:2165, 2176)
  → `MetadataService.cleanFileName` / `guessTrackInfo` (misma regex).
- `qualityLabel` (index.html:2129: FLAC/WAV/OGG/AAC/MP3/WEBM)
  → `Song.qualityLabel` (misma lógica). `formatSize` (2147) y
  `formatTime` (2114) → `Song.formattedSize` / `FlexpsFormat.time`.

## Vistas web → Swift

| Web (función / líneas) | Swift 1.0 |
|---|---|
| Dock: Inicio / Playlists / Buscar / Favoritos (`dockGoTo` 2646) | `ContentView` TabView, mismos 4 tabs |
| Home (`renderHome` 3160): acceso YouTube, playlists recientes, álbumes recientes | `HomeView` |
| Para ti (`renderForYou` 3234): más reproducidas, favoritas de la semana, álbumes y artistas recién agregados | `ForYouView` (misma lógica; favoritas de la semana = `favoritedAt` últimos 7 días) |
| Canciones (`renderSongsView` 3414) | `SongsListView` |
| Artistas / Álbumes (`renderGroupList` 3333) | `ArtistsListView` / `AlbumsListView` |
| Detalle artista / álbum (`renderArtistDetail` 3633, `renderAlbumDetail` 3641, `detailHero` 3118) | `ArtistDetailView` / `AlbumDetailView` |
| Favoritos | `FavoritesView` (canciones + playlists + álbumes + artistas favoritos) |
| Cola (`renderQueueView` 3489) | `QueueView` ("A continuación") |
| Playlists (`renderPlaylistsView` 3565, detalle 3622, `createPlaylist` 3661) | `PlaylistsView` / `PlaylistDetailView` |
| YouTube (`renderYouTubeView` 4548) | `YouTubeView` + `YouTubePlayerSheet` |
| Ajustes (hoja 4158-4264) | `SettingsView` |

## Búsqueda y orden

- Búsqueda global: canciones y artistas (input `search`, index.html:2755)
  → `SearchView` (canciones, artistas y álbumes).
- Orden (`applySort` 2566; opciones en el `<select id="sort">` 1390-1397):
  recientes, antiguas, canción A-Z / Z-A, artista A-Z / Z-A, tamaño
  → `SortMode` (mismos 7, mismo default: canción A-Z).

## Reproductor

- `<audio>` + `crossAudio` (1671), mini player, full player, seek,
  prev/next, shuffle, repeat off/all/one, cola, `MediaSession`
  (`updateMediaSession` 5082, handlers 5154) → `PlayerManager`
  (AVPlayer + segundo AVPlayer para crossfade, `MPNowPlayingInfoCenter` +
  `MPRemoteCommandCenter`), `MiniPlayerView`, `FullPlayerView`, `QueueView`.
- Crossfade on/off 1–12 s, default 4 s (1671-1674, 1984) → igual en
  `PlayerManager` + Ajustes (Stepper 1…12).
- Sleep timer: off / 15 / 30 / 45 / 60 min / al terminar la canción
  (secuencia en 4171; `setSleepTimer` 1694; NO persistente)
  → `SleepTimerOption` (mismas opciones, no persistente).
- Modo karaoke (5402-5407, CSS 1192-1213): letra a pantalla completa
  → `FullPlayerView.karaokeSection` con línea activa.
- Visualizador por analyser (`analyser` 1714, 4898-4924, Web Audio API)
  → **PENDIENTE en 1.0**: no se incluyó; en Swift sería AVAudioEngine
  con un tap. No se inventó uno falso.
- Badge de calidad → en `SongRowView` y full player.

## Letras

- LRCLib directo `https://lrclib.net/api/get?artist_name&track_name&album_name&duration`
  (4729, 4849), LRC sincronizado con línea activa, caché en store `lyrics`
  → `LyricsService` (misma URL y parámetros, `parseLRC`,
  `activeLineIndex`) + caché en `LibraryStore.lyricsCache`.
- "Actualizar letras" (bulk, `updateLibraryLyrics`) → Ajustes.

## Información musical

- Deezer directo `https://api.deezer.com/search?q=...&limit=25` con scoring
  por título/artista/álbum exacto (`api/music-info.js` completo;
  `searchMusicInfo` 2233, `updateSongInfo` 2319, `updateLibraryInfo` 2391)
  → `MetadataService.searchMusicInfo` (mismo scoring: título 20/8/5,
  artista 20/8/5, álbum 15/6/4, +2 portada, +2 foto artista; misma
  normalización sin diacríticos ni puntuación). Devuelve `albumCover`,
  `artistImage`, `releaseDate`, `source: "deezer"`.
- "Actualizar información" en Ajustes → `LibraryStore.updateAllInfo`.

## YouTube

- IFrame Player API oficial (`loadYouTubeAPI` 4385,
  `ensureYouTubePlayer` 4401, `onYouTubeState` 4425: ended → siguiente)
  → `YouTubePlayerView` (WKWebView, mismo flujo, ended → siguiente).
- Búsqueda por `/api/youtube-search` (`api/youtube-search.js`):
  `part=snippet`, `type=video`, `videoEmbeddable=true`,
  `videoCategoryId=10`, `maxResults=12`, necesita `YOUTUBE_API_KEY`
  → `YouTubeService.search` llama directo a
  `googleapis.com/youtube/v3/search` con los mismos parámetros y la clave
  que el usuario pega en Ajustes (UserDefaults, nunca en el repo).
  **No hay endpoint Vercel propio ni URL inventada.**
- Pegar enlace funciona SIN clave vía oEmbed
  (`songFromYouTubeLink` 4532-4548) → `YouTubeService.trackFromLink`.
- Últimos 40 tracks en memoria (`rememberYouTube` 4378)
  → `LibraryStore.recentYouTube` (máx. 40, en memoria).

## Ajustes

- Tema claro/oscuro (`applyTheme` 2000) → `AppTheme` sistema/claro/oscuro.
- Crossfade + duración, sleep timer, actualizar info, actualizar letras,
  ver almacenamiento (`checkStorage` 2539), borrar biblioteca, versión
  → `SettingsView` (mismas secciones).

## Lo que cambia por ser nativo (decisión, no omisión)

- Sin IndexedDB ni Blob: JSON + archivos en Documents.
- Sin jsmediatags: AVAsset commonMetadata.
- Sin MediaSession web: MPNowPlayingInfoCenter / MPRemoteCommandCenter.
- Sin AudioContext/analyser: visualizador pendiente (ver arriba).
- Sin servidor Vercel: la clave de YouTube vive en el teléfono.
