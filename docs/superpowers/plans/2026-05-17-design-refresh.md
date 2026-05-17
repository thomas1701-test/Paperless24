# Design Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernisierung des visuellen Erscheinungsbilds — Indigo-Akzentfarbe, tag-farbige Thumbnail-Gradienten auf Kacheln, angepasste Filter-Chips, saubere Light/Dark-Mode-Trennung.

**Architecture:** Vier unabhängige Änderungen: (1) AccentColor Asset, (2) DocumentCard visuelles Redesign, (3) Filter-Chip Styling in MainDocView. Keine neuen Typen oder Datenmodelle nötig — rein visuelle Änderungen.

**Tech Stack:** SwiftUI, Xcode Asset Catalog, `Color(hex:)` Extension (bereits vorhanden)

---

## Dateiübersicht

| Datei | Änderung |
|-------|---------|
| `Paperless TeDi/Assets.xcassets/AccentColor.colorset/Contents.json` | Indigo-Farbe light+dark eintragen |
| `Paperless TeDi/Views/Documents/DocumentCard.swift` | Gradient, Dot, Badge-Farbe, Radius, Hintergrund |
| `Paperless TeDi/Views/Documents/MainDocView.swift` | Filter-Chip Styling (Zeilen 341–368) |

> **Hinweis:** InboxView hat keine eigene FilterBar — nur MainDocView.

---

## Task 1: AccentColor auf Indigo setzen

**Files:**
- Modify: `Paperless TeDi/Assets.xcassets/AccentColor.colorset/Contents.json`

- [ ] **Schritt 1: Contents.json ersetzen**

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.710",
          "green" : "0.318",
          "red" : "0.247"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.753",
          "green" : "0.420",
          "red" : "0.361"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

> Light: `#3f51b5` (R=0.247 G=0.318 B=0.710) — Dark: `#5c6bc0` (R=0.361 G=0.420 B=0.753)

- [ ] **Schritt 2: App bauen und AccentColor prüfen**

In Xcode: Cmd+B. Dann im Simulator prüfen ob Buttons, Tab-Icons und Links jetzt Indigo statt Blau sind.

- [ ] **Schritt 3: Commit**

```bash
git add "Paperless TeDi/Assets.xcassets/AccentColor.colorset/Contents.json"
git commit -m "feat: AccentColor auf Indigo (#3f51b5 / #5c6bc0) setzen"
```

---

## Task 2: DocumentCard — Hilfsproperty für erste Tag-Farbe

**Files:**
- Modify: `Paperless TeDi/Views/Documents/DocumentCard.swift`

Diese Property wird von den folgenden Tasks 3–5 verwendet.

- [ ] **Schritt 1: Computed property `firstTagColor` einfügen**

Direkt vor `var body: some View {` einfügen:

```swift
private var firstTagColor: Color {
    guard let firstTagId = doc.tags.first,
          let tag = allTags.first(where: { $0.id == firstTagId }) else {
        return Color(.systemGray4)
    }
    return Color(hex: tag.safeColor)
}
```

- [ ] **Schritt 2: Bauen**

Cmd+B — muss fehlerfrei kompilieren.

- [ ] **Schritt 3: Commit**

```bash
git add "Paperless TeDi/Views/Documents/DocumentCard.swift"
git commit -m "refactor: firstTagColor helper property in DocumentCard"
```

---

## Task 3: DocumentCard — Thumbnail-Gradient + Höhe + Radius

**Files:**
- Modify: `Paperless TeDi/Views/Documents/DocumentCard.swift`

- [ ] **Schritt 1: AuthImage-Zeile anpassen**

Aktuell (Zeile ~19):
```swift
AuthImage(docId: doc.id, urlString: thumbUrl, token: token, contentMode: .fill)
    .frame(height: 100)
    .background(Color(.systemGray6))
    .clipped()
```

Ersetzen durch:
```swift
AuthImage(docId: doc.id, urlString: thumbUrl, token: token, contentMode: .fill)
    .frame(height: 80)
    .background(
        LinearGradient(
            colors: [firstTagColor.opacity(0.5), firstTagColor.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .clipped()
```

- [ ] **Schritt 2: cornerRadius von 10 auf 14 ändern**

Aktuell (in `body`):
```swift
.cornerRadius(10)
```

Ersetzen durch:
```swift
.cornerRadius(14)
```

Die `RoundedRectangle` im overlay ebenfalls anpassen:
```swift
.overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
```

- [ ] **Schritt 3: Bauen und im Simulator prüfen**

Cmd+R — Kacheln sollten jetzt farbige Thumbnail-Hintergründe und abgerundetere Ecken zeigen.

- [ ] **Schritt 4: Commit**

```bash
git add "Paperless TeDi/Views/Documents/DocumentCard.swift"
git commit -m "feat: DocumentCard Thumbnail-Gradient + Höhe 80pt + Radius 14pt"
```

---

## Task 4: DocumentCard — Korrespondenten-Dot

**Files:**
- Modify: `Paperless TeDi/Views/Documents/DocumentCard.swift`

- [ ] **Schritt 1: Korrespondenten-Zeile anpassen**

Aktuell (ca. Zeile 46–51):
```swift
if let cid = doc.correspondent, let name = allCorrespondents.first(where: { $0.id == cid })?.safeName {
    Text(name)
        .font(.system(size: 10))
        .foregroundColor(.accentColor)
        .lineLimit(1)
}
```

Ersetzen durch:
```swift
if let cid = doc.correspondent, let name = allCorrespondents.first(where: { $0.id == cid })?.safeName {
    HStack(spacing: 4) {
        Circle()
            .fill(firstTagColor)
            .frame(width: 6, height: 6)
        Text(name)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.accentColor)
            .lineLimit(1)
    }
}
```

- [ ] **Schritt 2: Bauen und prüfen**

Cmd+R — Korrespondenten-Name sollte jetzt mit kleinem farbigem Punkt davor erscheinen.

- [ ] **Schritt 3: Commit**

```bash
git add "Paperless TeDi/Views/Documents/DocumentCard.swift"
git commit -m "feat: farbiger Korrespondenten-Punkt in DocumentCard"
```

---

## Task 5: DocumentCard — Dokumenttyp-Badge farbig

**Files:**
- Modify: `Paperless TeDi/Views/Documents/DocumentCard.swift`

- [ ] **Schritt 1: Dokumenttyp-Badge Styling anpassen**

Aktuell (ca. Zeile 59–66):
```swift
if let tid = doc.documentType, let typeName = allDocTypes.first(where: { $0.id == tid })?.safeName {
    Text(typeName)
        .font(.system(size: 9))
        .foregroundColor(.secondary)
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(Color(.systemGray5))
        .cornerRadius(4)
} else {
    Color.clear.frame(height: 16)
}
```

Ersetzen durch:
```swift
if let tid = doc.documentType, let typeName = allDocTypes.first(where: { $0.id == tid })?.safeName {
    Text(typeName)
        .font(.system(size: 9, weight: .semibold))
        .foregroundColor(firstTagColor)
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(firstTagColor.opacity(0.15))
        .cornerRadius(4)
} else {
    Color.clear.frame(height: 16)
}
```

- [ ] **Schritt 2: Bauen und prüfen**

Cmd+R — Dokumenttyp-Badge sollte jetzt in der Farbe des ersten Tags erscheinen.

- [ ] **Schritt 3: Commit**

```bash
git add "Paperless TeDi/Views/Documents/DocumentCard.swift"
git commit -m "feat: Dokumenttyp-Badge farbig nach erstem Tag"
```

---

## Task 6: DocumentCard — Light/Dark Mode Hintergrund

**Files:**
- Modify: `Paperless TeDi/Views/Documents/DocumentCard.swift`

- [ ] **Schritt 1: `@Environment` hinzufügen**

Direkt nach den `let`/`var` Properties (vor `firstTagColor`) einfügen:

```swift
@Environment(\.colorScheme) private var colorScheme
```

- [ ] **Schritt 2: Hintergrund und Shadow ersetzen**

Aktuell:
```swift
.background(Material.thickMaterial)
.cornerRadius(14)
.shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
.overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
```

Ersetzen durch:
```swift
.background(Color(UIColor.secondarySystemBackground))
.cornerRadius(14)
.shadow(
    color: colorScheme == .dark ? .clear : Color.black.opacity(0.07),
    radius: 5, x: 0, y: 2
)
.overlay(
    RoundedRectangle(cornerRadius: 14)
        .stroke(
            isSelected ? Color.accentColor : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.clear),
            lineWidth: isSelected ? 2 : 1
        )
)
```

- [ ] **Schritt 3: Im Simulator Light und Dark Mode prüfen**

Cmd+R → im Simulator über Features > Toggle Appearance zwischen Light und Dark wechseln.

- Light Mode: weiße Karte mit leichtem Schatten, kein Border
- Dark Mode: #2c2c2e Karte, feiner weißer Border, kein Schatten

- [ ] **Schritt 4: Commit**

```bash
git add "Paperless TeDi/Views/Documents/DocumentCard.swift"
git commit -m "feat: DocumentCard Light/Dark-Mode Hintergrund ohne Material.thickMaterial"
```

---

## Task 7: MainDocView — Filter-Chip Styling

**Files:**
- Modify: `Paperless TeDi/Views/Documents/MainDocView.swift` (Zeilen 341–387)

- [ ] **Schritt 1: Hilfsfunktion für Chip-Styling einfügen**

Direkt vor `var filterBar: some View {` (ca. Zeile 328) einfügen:

```swift
private func chipBackground(active: Bool) -> Color {
    active ? Color.accentColor : Color.accentColor.opacity(0.1)
}

private func chipForeground(active: Bool) -> Color {
    active ? .white : .accentColor
}
```

- [ ] **Schritt 2: Zeitraum-Chip anpassen**

Aktuell (Zeile ~342–348):
```swift
HStack {
    Image(systemName: "calendar")
    Text(filterDate == .all ? "Zeitraum" : filterDate.rawValue)
}
.padding(.horizontal, 10).padding(.vertical, 6)
.background(Material.thickMaterial).cornerRadius(20)
```

Ersetzen durch:
```swift
HStack {
    Image(systemName: "calendar")
    Text(filterDate == .all ? "Zeitraum" : filterDate.rawValue)
}
.font(.system(size: 13, weight: .medium))
.foregroundColor(chipForeground(active: filterDate != .all))
.padding(.horizontal, 12).padding(.vertical, 7)
.background(chipBackground(active: filterDate != .all))
.cornerRadius(8)
```

- [ ] **Schritt 3: Tags-Chip anpassen**

Aktuell (Zeile ~350–355):
```swift
Label(filterTag == nil ? "Tags" : ..., systemImage: "tag")
    .padding(.horizontal, 12).padding(.vertical, 8)
    .background(filterTag == nil ? AnyShapeStyle(Material.thickMaterial) : AnyShapeStyle(Color.accentColor.opacity(0.2)))
    .cornerRadius(20)
```

Ersetzen durch:
```swift
Label(filterTag == nil ? "Tags" : (store.allTags.first { $0.id == filterTag }?.safeName ?? "Tag"), systemImage: "tag")
    .font(.system(size: 13, weight: .medium))
    .foregroundColor(chipForeground(active: filterTag != nil))
    .padding(.horizontal, 12).padding(.vertical, 7)
    .background(chipBackground(active: filterTag != nil))
    .cornerRadius(8)
```

- [ ] **Schritt 4: Sender-Chip anpassen**

Aktuell (Zeile ~357–362):
```swift
Label(filterCorr == nil ? "Sender" : ..., systemImage: "person")
    .padding(.horizontal, 12).padding(.vertical, 8)
    .background(filterCorr == nil ? AnyShapeStyle(Material.thickMaterial) : AnyShapeStyle(Color.accentColor.opacity(0.2)))
    .cornerRadius(20)
```

Ersetzen durch:
```swift
Label(filterCorr == nil ? "Sender" : (store.allCorrespondents.first { $0.id == filterCorr }?.safeName ?? "Sender"), systemImage: "person")
    .font(.system(size: 13, weight: .medium))
    .foregroundColor(chipForeground(active: filterCorr != nil))
    .padding(.horizontal, 12).padding(.vertical, 7)
    .background(chipBackground(active: filterCorr != nil))
    .cornerRadius(8)
```

- [ ] **Schritt 5: Typ-Chip anpassen**

Aktuell (Zeile ~364–369):
```swift
Label(filterType == nil ? "Typ" : ..., systemImage: "doc")
    .padding(.horizontal, 12).padding(.vertical, 8)
    .background(filterType == nil ? AnyShapeStyle(Material.thickMaterial) : AnyShapeStyle(Color.accentColor.opacity(0.2)))
    .cornerRadius(20)
```

Ersetzen durch:
```swift
Label(filterType == nil ? "Typ" : (store.allDocTypes.first { $0.id == filterType }?.safeName ?? "Typ"), systemImage: "doc")
    .font(.system(size: 13, weight: .medium))
    .foregroundColor(chipForeground(active: filterType != nil))
    .padding(.horizontal, 12).padding(.vertical, 7)
    .background(chipBackground(active: filterType != nil))
    .cornerRadius(8)
```

- [ ] **Schritt 6: Bauen und Filter-Chips prüfen**

Cmd+R — inaktive Chips: Indigo-Text auf hellblauem Grund. Aktiver Chip (z.B. Tag ausgewählt): weiß auf Indigo. Kein `Material.thickMaterial` mehr.

- [ ] **Schritt 7: Commit**

```bash
git add "Paperless TeDi/Views/Documents/MainDocView.swift"
git commit -m "feat: Filter-Chips mit Indigo-Akzent, filled wenn aktiv"
```

---

## Abschluss-Check

- [ ] App im Light Mode durchscrollen — alle Kacheln gleichmäßig, Farben konsistent
- [ ] App im Dark Mode durchscrollen — #2c2c2e Karten, kein Material-Blur-Effekt sichtbar
- [ ] Filter setzen — aktiver Chip sollte filled Indigo zeigen
- [ ] Dokument ohne Tags — Kachel zeigt neutralen Grau-Gradient (Fallback)
- [ ] Dokument ohne Dokumenttyp — kein Badge, aber Platzhalterhöhe bleibt (Color.clear)
