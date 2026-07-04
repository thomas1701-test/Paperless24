# Paperless TeDi für Android — Design (Phase 1: MVP)

## Kontext

Paperless TeDi ist eine native iOS/SwiftUI-App für Paperless-ngx. Eine 1:1-Portierung ist
nicht möglich: mehrere Kernfeatures hängen an Apple-exklusiven Frameworks (Apple
Intelligence/FoundationModels, WidgetKit, AppIntents/Siri, iCloud-Sync, SwiftUI-Übersetzung,
StoreKit-Review). Statt eines 1:1-Ports wird eine eigenständige native Android-App gebaut,
die dieselbe Paperless-ngx-Server-API konsumiert und dieselben Kernaufgaben mit
Android-eigenen Mitteln löst. Große Nicht-MVP-Features (Widget, Notifications/Sync,
semantische Suche, Übersetzung, AirScan, Tablet-Split-View, Assistant-Shortcuts) werden
als spätere, eigene Specs behandelt.

## Tech-Stack

- Kotlin + Jetpack Compose (Material 3)
- MVVM + Repository-Pattern: `ui/` → `viewmodel/` → `repository/` → `network/` (Retrofit +
  OkHttp) + `data/local/` (Room für Offline-Cache)
- Multi-Account: Room-Tabelle für Accounts (Server-URL, Token), Secrets in
  `EncryptedSharedPreferences`/Android Keystore (Äquivalent zum iOS-Keychain-Ansatz)
- Projektpfad: `android/` im bestehenden Repo, eigenes Gradle-Root, unabhängig vom
  Xcode-Projekt

## Auth & API

Server-API ist Standard-Paperless-ngx, 1:1 nach `Paperless24/Services/PaperlessAPI.swift`:

- `POST /api/token/` mit `username`/`password` (+ optionalem `code` bei 2FA) → Token
- Alle weiteren Requests: Header `Authorization: Token <token>`
- Connection-Check optional via Basic-Auth gegen `/api/tags/`
- Dokumente: `GET /api/documents/?page=&page_size=&ordering=`, Suche über `?query=`

## MVP-Feature-Scope (Phase 1)

1. Login / Multi-Account (Server-URL, Token-Auth, 2FA-Code)
2. Dokumentenliste (paginiert, Sortierung, Suche) + Detailansicht (PDF-Anzeige)
3. Tags / Korrespondenten / Dokumenttypen verwalten (CRUD gegen Standard-API)
4. Upload aus Galerie/Dateien
5. Kamera-Scanner via ML Kit Document Scanner API (Kantenerkennung, Perspektivkorrektur,
   Multi-Page) — Android-Pendant zu VisionKit
6. Biometrische Sperre via BiometricPrompt
7. KI-Basis (Zusammenfassung + Auto-Tagging): Adapter-Schicht, die zuerst Gemini Nano
   (on-device, AICore) versucht, sonst auf Cloud-API mit nutzereigenem API-Key zurückfällt
   (Einstellungsfeld analog zum iOS-Ansatz)

## Spätere Phasen (nicht Teil dieser Spec)

Home-Screen-Widget, Notifications/WorkManager-Sync, semantische Archiv-Suche, Übersetzung,
AirScan/eSCL-Netzwerkscanner-Discovery, Tablet-Split-View, Google-Assistant-Shortcuts.

## Testing

- Unit-Tests für Repository/ViewModel (JUnit + Turbine für Flows)
- Kein automatisiertes UI-Testing im MVP; manuelle Verifikation im Android-Emulator nach
  jedem Feature

## Vorgehen / Entscheidungsdelegation

Der Nutzer hat entschieden, alle weiteren Detailentscheidungen (Paketname, Modulaufteilung,
konkrete Library-Versionen, Reihenfolge der Umsetzung innerhalb der Phase) an den
Implementierenden zu delegieren, und möchte erst wieder informiert werden, sobald die App
im Emulator lauffähig und testbar ist.
