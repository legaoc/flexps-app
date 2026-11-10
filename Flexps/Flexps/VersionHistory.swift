import Foundation

// Historial de versiones de la app Swift.
// La web está en v1.6.2 (index.html:1568, APP_VERSION).
// La versión Swift empieza en 1.0 y sigue su propio número.

struct VersionEntry: Identifiable {
    var id: String { version }
    let version: String
    let date: String
    let notes: [String]
}

enum VersionHistory {
    static let current = "1.0.8"
    static let webVersion = "1.6.2"

    static let entries: [VersionEntry] = [
        VersionEntry(
            version: "1.0.8",
            date: "9 nov 2026",
            notes: [
                "Visualizador de audio, como en la web: la portada queda estática y el fondo borroso detrás respira con la energía de la música (escala, rotación, saturación y brillo).",
                "La energía real se lee con un tap de solo lectura sobre el reproductor, sin tocar el crossfade ni la reproducción en segundo plano; sin espectro (YouTube) respira por seno, como en la web."
            ]
        ),
        VersionEntry(
            version: "1.0.7",
            date: "8 nov 2026",
            notes: [
                "En modo oscuro los iconos ya se ven blancos: el color de acento era negro fijo y la pestaña seleccionada desaparecía sobre el fondo oscuro."
            ]
        ),
        VersionEntry(
            version: "1.0.6",
            date: "8 nov 2026",
            notes: [
                "El mini reproductor quedó un poco más arriba, con más aire sobre el menú de abajo."
            ]
        ),
        VersionEntry(
            version: "1.0.5",
            date: "8 nov 2026",
            notes: [
                "El mini reproductor ya no tapa el menú de abajo (la barra flotante de iOS 26)."
            ]
        ),
        VersionEntry(
            version: "1.0.4",
            date: "8 nov 2026",
            notes: [
                "Ahora se puede importar música con Compartir o Abrir con desde Archivos y otras apps, directo a la biblioteca."
            ]
        ),
        VersionEntry(
            version: "1.0.3",
            date: "8 nov 2026",
            notes: [
                "Icono de la app con el PNG real de iPlay (oscuro con el logo tal cual, claro en negativo) y el logo también dentro de la app, en Inicio.",
                "Importar desde el selector ahora es con un solo toque: antes solo se marcaba la canción y había que pulsar Abrir."
            ]
        ),
        VersionEntry(
            version: "1.0.2",
            date: "8 nov 2026",
            notes: [
                "La app ahora se llama iPlayerPod en todas partes (antes aparecía como Flexps)."
            ]
        ),
        VersionEntry(
            version: "1.0.1",
            date: "8 nov 2026",
            notes: [
                "Se corrigió la importación: los archivos MP4 ahora aparecen en el picker y se pueden importar, como en la web.",
                "El resultado de la importación siempre se muestra: al terminar sale un aviso con cuántas canciones se importaron o por qué no se pudo importar."
            ]
        ),
        VersionEntry(
            version: "1.0",
            date: "8 nov 2026",
            notes: [
                "Primera versión nativa en Swift (SwiftUI, iOS 17), reescritura de la web iPlayerPod v1.6.2.",
                "Biblioteca 100% local: importar MP3, M4A, WAV, AAC, FLAC y MP4; metadatos y portada embebida con AVAsset; archivos guardados en Documents/Music.",
                "Canciones, artistas, álbumes, favoritos, búsqueda global y los 7 órdenes de la web.",
                "Playlists con crear, renombrar, eliminar y agregar/quitar canciones; recientes y favoritos de playlists, álbumes y artistas.",
                "Para ti: más reproducidas, favoritas de la semana, álbumes y artistas recién agregados.",
                "Reproductor nativo con AVPlayer: cola, aleatorio, repetir (todo/una), crossfade 1–12 s, temporizador de apagado, modo karaoke con letra sincronizada.",
                "Letras con LRCLib (sincronizadas y en texto plano) con caché local.",
                "Información musical con Deezer (portada de álbum, foto de artista, fecha de lanzamiento) con el mismo scoring de la web.",
                "YouTube con el reproductor oficial IFrame en WKWebView: pegar enlace funciona sin clave (oEmbed); la búsqueda usa tu clave de YouTube Data API v3 guardada en Ajustes.",
                "Tema claro/oscuro, almacenamiento, borrar biblioteca. Sin cuenta, sin Firebase, sin servidores propios."
            ]
        )
    ]
}
