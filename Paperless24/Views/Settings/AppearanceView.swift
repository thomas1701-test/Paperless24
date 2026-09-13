import SwiftUI
import WidgetKit

/// Alle Darstellungs-Einstellungen an einem Ort: Farbthema, Hell/Dunkel, OLED-Schwarz,
/// Kachelgröße, die Lese-Einstellungen für PDF und OCR-Text, die Angaben in der Liste und
/// die Sprache.
struct AppearanceView: View {
    @Environment(\.colorScheme) private var systemScheme

    @AppStorage("themeId") private var themeId = AppTheme.indigo.rawValue
    @AppStorage("customAccentHex") private var customAccentHex = "3F51B5"
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @AppStorage("amoledEnabled") private var amoledEnabled = false
    @AppStorage("gridItemSize") private var gridItemSize: Double = 130
    @AppStorage("pdfDarkMode") private var pdfDarkMode = false
    @AppStorage("readingMode") private var readingMode = false
    @AppStorage("readingFontSize") private var readingFontSize: Double = 17
    @AppStorage("rowShowCorrespondent") private var rowShowCorrespondent = true
    @AppStorage("rowShowDate") private var rowShowDate = true
    @AppStorage("rowShowType") private var rowShowType = false
    @AppStorage("rowShowASN") private var rowShowASN = false
    @AppStorage("rowShowAdded") private var rowShowAdded = false
    @AppStorage("appLanguage") private var appLanguage = ""

    @State private var selectedIcon: AppIconOption = AppIconService.current

    private var theme: AppTheme { AppTheme(rawValue: themeId) ?? .indigo }
    private var isDark: Bool { isDarkAppearance(mode: appearanceMode, system: systemScheme) }

    /// Die Vorschau nutzt nicht die Umgebungs-Palette, sondern rechnet selbst — sonst hinkt
    /// sie beim Umschalten eine Auswahl hinterher.
    private var preview: ThemePalette {
        ThemeSettings(theme: theme, customAccentHex: customAccentHex, amoled: amoledEnabled)
            .palette(isDark: isDark)
    }

    var body: some View {
        Form {
            Section("Vorschau") {
                ThemePreviewCard(palette: preview)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 12) {
                    ForEach(AppTheme.allCases) { candidate in
                        ThemeSwatch(
                            theme: candidate,
                            isDark: isDark,
                            customHex: customAccentHex,
                            isSelected: candidate == theme
                        )
                        .onTapGesture {
                            themeId = candidate.rawValue
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        // Stabiler Anker für die UI-Tests: der sichtbare Name ist übersetzt.
                        .accessibilityIdentifier("theme-\(candidate.rawValue)")
                    }
                }
                .padding(.vertical, 4)

                if theme == .custom {
                    ColorPicker("Eigene Farbe", selection: Binding(
                        get: { Color(hex: ThemeSettings.sanitize(customAccentHex)) },
                        set: { customAccentHex = $0.hexString }
                    ), supportsOpacity: false)
                }
            } header: {
                Text("Farbthema")
            } footer: {
                Text("Tag-Farben kommen vom Server und bleiben unverändert.")
            }

            Section {
                Picker("Design", selection: $appearanceMode) {
                    Text("Auto").tag(0)
                    Text("Hell").tag(1)
                    Text("Dunkel").tag(2)
                }
                .pickerStyle(.segmented)

                Toggle("Schwarzer Hintergrund", isOn: $amoledEnabled)
            } header: {
                Text("Erscheinungsbild")
            } footer: {
                Text("Schwarzer Hintergrund spart auf OLED-Displays Strom und wirkt nur im Dunkelmodus.")
            }

            if AppIconService.isSupported {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(AppIconOption.allCases) { option in
                                Button {
                                    AppIconService.set(option)
                                    selectedIcon = option
                                } label: {
                                    AppIconTile(option: option, isSelected: selectedIcon == option)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("App-Symbol")
                }
            }

            Section("Raster") {
                VStack(alignment: .leading) {
                    Text("Kachelgröße").font(.subheadline)
                    Slider(value: $gridItemSize, in: 90...260, step: 10)
                    Text("\(Int(gridItemSize)) pt").font(.caption).foregroundColor(.secondary)
                }
            }

            Section {
                Toggle("PDF im Dunkelmodus abdunkeln", isOn: $pdfDarkMode)
                Toggle("Lesemodus für den Text-Reiter", isOn: $readingMode)
                if readingMode {
                    VStack(alignment: .leading) {
                        Text("Schriftgröße").font(.subheadline)
                        Slider(value: $readingFontSize, in: 14...26, step: 1)
                        Text("\(Int(readingFontSize)) pt").font(.caption).foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Lesen")
            } footer: {
                Text("Der Lesemodus zeigt den erkannten Text auf warmem Papierton mit größerer Schrift.")
            }

            Section {
                Toggle("Sender", isOn: $rowShowCorrespondent)
                Toggle("Typ", isOn: $rowShowType)
                Toggle("Belegdatum", isOn: $rowShowDate)
                Toggle("Hinzugefügt am", isOn: $rowShowAdded)
                Toggle("ASN", isOn: $rowShowASN)
            } header: {
                Text("Angaben in der Liste")
            } footer: {
                Text("Gilt für die Listenansicht. Bei einer Suche steht an dieser Stelle der Textausschnitt mit dem Suchbegriff.")
            }

            Section("Sprache") {
                Picker("Sprache", selection: $appLanguage) {
                    Text("🌐 Systemsprache").tag("")
                    Text("🇩🇪 Deutsch").tag("de")
                    Text("🇬🇧 English").tag("en")
                    Text("🇫🇷 Français").tag("fr")
                    Text("🇪🇸 Español").tag("es")
                    Text("🇮🇹 Italiano").tag("it")
                }
            }
        }
        .navigationTitle("Darstellung")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: themeId) { _, _ in syncWidgetTheme() }
        .onChange(of: customAccentHex) { _, _ in syncWidgetTheme() }
    }

    /// Das Widget hat keinen Zugriff auf `UserDefaults.standard`; es liest die fertige Farbe
    /// aus der App-Group und muss danach neu gezeichnet werden.
    private func syncWidgetTheme() {
        let settings = ThemeSettings(theme: theme, customAccentHex: customAccentHex, amoled: amoledEnabled)
        WidgetDataService.writeTheme(
            accentLightHex: settings.accentHex(isDark: false),
            accentDarkHex: settings.accentHex(isDark: true)
        )
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Vorschau eines App-Symbols.
private struct AppIconTile: View {
    let option: AppIconOption
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image = option.previewImage {
                    Image(uiImage: image).resizable()
                } else {
                    RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.2))
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: isSelected ? 3 : 1)
            )

            Text(option.displayName)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 68)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Ein Farbfeld im Themenraster.
private struct ThemeSwatch: View {
    let theme: AppTheme
    let isDark: Bool
    let customHex: String
    let isSelected: Bool

    private var accent: Color {
        theme == .custom
            ? Color(hex: ThemeSettings.sanitize(customHex))
            : Color(hex: theme.accentHex(isDark: isDark))
    }

    private var fill: LinearGradient {
        let colors = theme.gradientHexes.isEmpty
            ? [accent, accent.opacity(0.75)]
            : theme.gradientHexes.map { Color(hex: $0) }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(fill)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .frame(height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? accent : Color.secondary.opacity(0.25),
                            lineWidth: isSelected ? 3 : 1)
            )

            Text(theme.displayName)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Zeigt in klein, was das Thema mit Verlauf, Chips und Karte macht.
private struct ThemePreviewCard: View {
    let palette: ThemePalette

    var body: some View {
        ZStack {
            if let surface = palette.surface {
                surface
            } else if palette.hasGradient {
                LinearGradient(
                    colors: palette.gradient.map { $0.opacity(0.12) },
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            } else {
                Color(.secondarySystemBackground)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    previewChip("Zeitraum", active: false)
                    previewChip("Tags", active: true)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemBackground))
                        .frame(width: 44, height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(palette.strongEdges ? palette.accent.opacity(0.55) : Color.secondary.opacity(0.2),
                                        lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rechnung Mai").font(.caption).fontWeight(.semibold)
                        Text("Stadtwerke").font(.caption2).foregroundColor(palette.accent)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill").foregroundColor(palette.accent)
                }
            }
            .padding(12)
        }
        .frame(height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// `LocalizedStringKey` — als `String` blieb die Beschriftung in jeder Sprache deutsch.
    private func previewChip(_ title: LocalizedStringKey, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(palette.chipForeground(active: active))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(palette.chipBackground(active: active))
            .cornerRadius(8)
    }
}
