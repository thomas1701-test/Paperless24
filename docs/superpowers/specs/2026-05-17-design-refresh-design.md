# Design Refresh — Paperless TeDi

**Datum:** 2026-05-17  
**Status:** Genehmigt

---

## Ziel

Modernisierung des visuellen Erscheinungsbilds der App. Die App soll professioneller, moderner und kohärenter wirken — sowohl im Light als auch im Dark Mode.

---

## Design-Entscheidungen

### 1. Akzentfarbe: Indigo

| Modus | Farbe | Hex |
|-------|-------|-----|
| Light | Indigo | `#3f51b5` |
| Dark | Indigo Light | `#5c6bc0` |
| Light (Link/subtle) | Indigo Tint | `#9fa8da` (nur für sekundäre Texte im Dark Mode) |

Wird gesetzt als Custom Asset `AccentColor` in `Assets.xcassets`.

### 2. DocumentCard — neues Layout

**Thumbnail-Bereich:**
- Höhe: **80pt** (aktuell 100pt → leicht reduziert für bessere Proportion mit dem 72pt Textbereich)
- Hintergrund: Farbverlauf basierend auf der Farbe des ersten Tags (`linear-gradient` von Tag-Farbe mit 50% Opacity nach 20%)
- Falls kein Tag: neutraler Systemgrau-Verlauf
- Tags unten links als Pills (bereits vorhanden, bleibt)
- Corner Radius: **14pt** (von 10pt)

**Text-Bereich:**
- Korrespondent: kleiner farbiger Punkt (Tag-Farbe des Korrespondenten oder Indigo-Fallback) + Name in Indigo
- Titel: `font(.system(size: 12, weight: .heavy))`, 2 Zeilen
- Dokumenttyp-Badge: Hintergrundfarbe = Tag-Farbe mit 15% Opacity, Textfarbe = Tag-Farbe (statt grau)
- Datum: rechts unten, sekundäre Farbe
- Feste Höhe des Textbereichs: 72pt (bereits implementiert)

**Dark Mode spezifisch:**
- Kartenhintergrund: `Color(UIColor.secondarySystemBackground)` → ergibt `#2c2c2e`
- Border: `Color.white.opacity(0.06)`
- Kein `Material.thickMaterial` mehr (zu unscharf im Dark Mode)

**Light Mode spezifisch:**
- Kartenhintergrund: `Color(UIColor.systemBackground)` → weiß
- Shadow: `Color.black.opacity(0.07), radius: 5, y: 2`
- Kein Border

### 3. Filter-Chips (MainDocView)

- Aktiver Chip: Indigo filled (`background: .accentColor`, `foreground: .white`)
- Inaktiver Chip: Indigo tint (`background: Color.accentColor.opacity(0.1)`, `foreground: .accentColor`)
- Corner Radius: 8pt (von ~15pt)

### 4. Dark Mode Hintergrund

- Haupthintergrund: `Color(UIColor.systemGroupedBackground)` → `#1c1c1e`
- Karten: `Color(UIColor.secondarySystemBackground)` → `#2c2c2e`
- Kein `Material.thickMaterial` für Karten

### 5. Card Corner Radius

Alle Dokumentkarten: `14pt` (von `10pt`).

---

## Betroffene Dateien

| Datei | Änderung |
|-------|---------|
| `Assets.xcassets/AccentColor` | Indigo `#3f51b5` / `#5c6bc0` |
| `DocumentCard.swift` | Gradient-Thumbnail, Korrespondenten-Punkt, Badge-Farbe, Radius, Dark-Mode-Background |
| `MainDocView.swift` | Filter-Chip Styling |
| `InboxView.swift` | Gleiche Filter-Chip Anpassung wie MainDocView |

---

## Nicht in Scope

- LoginView, WelcomeView
- DocumentDetailView (PDF-Viewer)
- SettingsView, AccountsView
- DocumentRow (Listenansicht) — kann später in einem separaten Ticket folgen

---

## Technische Hinweise

- **Tag-Farbe für Gradient:** Ersten Tag des Dokuments via `allTags.first(where: { $0.id == doc.tags.first })` → `Color(hex: tag.safeColor)`. Fallback: `Color(.systemGray5)`.
- **Korrespondenten-Punkt:** Farbe = erste Tag-Farbe des Dokuments, nicht des Korrespondenten (Korrespondent hat keine eigene Farbe in der API). Fallback: `.accentColor`.
- **Dokumenttyp-Badge-Farbe:** Gleiche Tag-Farbe wie Thumbnail-Gradient. Fallback: Systemgrau.
- **AccentColor:** Wird in `Assets.xcassets` mit zwei Appearance-Varianten (Any/Light + Dark) gesetzt.
