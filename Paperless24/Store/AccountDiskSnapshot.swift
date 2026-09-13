import Foundation

/// Der auf der Platte liegende Stand eines Kontos, in einem Zug gelesen.
///
/// Eigener Typ, damit das Dekodieren in einer `Task.detached` laufen kann und der `AppStore`
/// die Werte danach in einem einzigen Schritt übernimmt — statt acht JSON-Dateien synchron
/// im `init` zu lesen und damit den App-Start aufzuhalten.
///
/// `@unchecked Sendable`: alle Felder sind unveränderliche Arrays aus Werttypen. Die einzelnen
/// Modelle sind (noch) nicht als `Sendable` deklariert, das nachzuziehen wäre eine eigene
/// Änderungsrunde durch alle Modelldateien.
struct AccountDiskSnapshot: @unchecked Sendable {
    let accountId: UUID
    let documents: [Document]
    let tags: [Tag]
    let correspondents: [Correspondent]
    let docTypes: [DocumentType]
    let customFields: [CustomField]
    let pendingUploads: [PendingUpload]
    let pendingEdits: [PendingEdit]
    let savedFilters: [SavedFilter]

    init(accountId id: UUID) {
        func url(_ name: String) -> URL {
            PersistenceService.accountDataURL(for: id, filename: name)
        }
        accountId = id
        PersistenceService.waitForPendingWrites()
        // Die Warteschlangen zuerst: Sie sind klein und ihr Verlust wäre am schmerzhaftesten.
        // Standen sie hinter dem großen `documents.json`, lagen zwischen Start und Lesen
        // leicht einige hundert Millisekunden.
        pendingUploads = PersistenceService.loadUploads(accountId: id)
        pendingEdits   = PersistenceService.load([PendingEdit].self,    fromURL: url("edits.json"))         ?? []
        savedFilters   = PersistenceService.load([SavedFilter].self,    fromURL: url("savedfilters.json"))  ?? []
        // `uniquedByID()` bereinigt auch Caches, die noch mit Dubletten aus einer früheren
        // App-Version geschrieben wurden — sonst überlebt der Fehler den Fix.
        documents      = (PersistenceService.load([Document].self,      fromURL: url("documents.json")) ?? []).uniquedByID()
        tags           = PersistenceService.load([Tag].self,            fromURL: url("tags.json"))          ?? []
        correspondents = PersistenceService.load([Correspondent].self,  fromURL: url("corrs.json"))         ?? []
        docTypes       = PersistenceService.load([DocumentType].self,   fromURL: url("types.json"))         ?? []
        customFields   = PersistenceService.load([CustomField].self,    fromURL: url("customfields.json"))  ?? []
    }
}
