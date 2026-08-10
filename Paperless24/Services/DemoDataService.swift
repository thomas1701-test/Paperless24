import UIKit
import PDFKit

/// Beispieldaten für den Demo-Modus.
///
/// Alle Absender, Beträge, Aktenzeichen und Adressen sind frei erfunden. Es werden
/// keine echten Personen-, Firmen- oder Bankdaten verwendet — die Daten dienen dem
/// Ausprobieren ohne Server und den Store-Screenshots.
///
/// `materialize` erzeugt zu jedem Beispieldokument lokal ein PDF im Dokument-Cache
/// des Demo-Kontos und legt die Miniaturansicht im `ImageCache` ab. Dadurch zeigen
/// Liste, Raster und Detailansicht echte Seiten statt grauer Platzhalter, ohne dass
/// eine Netzwerkverbindung nötig wäre.
///
/// Die Inhalte gibt es auf Deutsch und Englisch. Welche Fassung greift, entscheidet
/// die in den Einstellungen gewählte Sprache (`appLanguage`), sonst die Systemsprache.
enum DemoDataService {

    // MARK: - Sprache

    /// Zweisprachiger Text. Ein einzelnes Literal gilt für beide Sprachen (z. B. Eigennamen).
    struct LText: ExpressibleByStringLiteral {
        let de: String
        let en: String

        init(stringLiteral value: String) { de = value; en = value }
        init(_ de: String, _ en: String) { self.de = de; self.en = en }

        var text: String { DemoDataService.usesEnglish ? en : de }
    }

    static var usesEnglish: Bool {
        let selected = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        let code = selected.isEmpty
            ? (Locale.current.language.languageCode?.identifier ?? "de")
            : String(selected.prefix(2))
        return code == "en"
    }

    // MARK: - Ergebnis

    struct Content {
        let tags: [Tag]
        let correspondents: [Correspondent]
        let docTypes: [DocumentType]
        let customFields: [CustomField]
        let documents: [Document]
        let statistics: PaperlessStatistics
    }

    // MARK: - Stammdaten

    private enum TagID {
        static let invoice = 1, tax = 2, insurance = 3, home = 4, car = 5
        static let health = 6, contract = 7, warranty = 8, bank = 9, important = 10
        static let work = 11, utilities = 12
    }

    private enum CorrID {
        static let utilities = 1, taxOffice = 2, nordlicht = 3, fonline = 4, bank = 5
        static let dentist = 6, lindenhof = 7, garage = 8, electronics = 9, healthInsurer = 10
        static let mailOrder = 11, employer = 12
    }

    private enum TypeID {
        static let invoice = 1, contract = 2, notice = 3, policy = 4
        static let statement = 5, payslip = 6, receipt = 7, certificate = 8
    }

    private enum FieldID {
        static let amount = 1, dueDate = 2, contractNo = 3, paid = 4
    }

    private static let tagNames: [(Int, LText, String, Int?)] = [
        (TagID.invoice,   LText("Rechnung", "Invoice"),      "#E4572E", nil),
        (TagID.tax,       LText("Steuer", "Tax"),            "#7B2CBF", nil),
        (TagID.insurance, LText("Versicherung", "Insurance"), "#1B6CA8", nil),
        (TagID.home,      LText("Wohnung", "Home"),          "#2A9D8F", nil),
        (TagID.car,       LText("Auto", "Car"),              "#E9A020", nil),
        (TagID.health,    LText("Gesundheit", "Health"),     "#D1495B", nil),
        (TagID.contract,  LText("Vertrag", "Contract"),      "#3A6EA5", nil),
        (TagID.warranty,  LText("Garantie", "Warranty"),     "#C46210", nil),
        (TagID.bank,      LText("Bank", "Banking"),          "#2F4858", nil),
        (TagID.important, LText("Wichtig", "Important"),     "#B3001B", nil),
        (TagID.work,      LText("Arbeit", "Work"),           "#4C6663", nil),
        // Verschachtelt unter „Wohnung" — zeigt die Tag-Hierarchie in der Verwaltung.
        (TagID.utilities, LText("Nebenkosten", "Utilities"), "#67A47B", TagID.home)
    ]

    static var tags: [Tag] {
        tagNames.map { Tag(id: $0.0, name: $0.1.text, color: $0.2, parent: $0.3) }
    }

    private static let correspondentNames: [(Int, LText)] = [
        (CorrID.utilities,     LText("Stadtwerke Musterstadt", "Sampleton City Utilities")),
        (CorrID.taxOffice,     LText("Finanzamt Musterstadt", "Sampleton Tax Office")),
        (CorrID.nordlicht,     "Nordlicht Versicherung AG"),
        (CorrID.fonline,       LText("Fonline Mobilfunk", "Fonline Mobile")),
        (CorrID.bank,          LText("Musterbank AG", "Sample Bank plc")),
        (CorrID.dentist,       LText("Zahnarztpraxis Dr. Berger", "Dr. Berger Dental Practice")),
        (CorrID.lindenhof,     LText("Hausverwaltung Lindenhof", "Lindenhof Property Management")),
        (CorrID.garage,        LText("Kfz-Werkstatt Kranz", "Kranz Auto Repair")),
        (CorrID.electronics,   LText("Elektrohaus Volt & Watt", "Volt & Watt Electronics")),
        (CorrID.healthInsurer, LText("Krankenkasse Nordsee", "Nordsee Health Insurance")),
        (CorrID.mailOrder,     LText("Musterversand GmbH", "Sample Mail Order Ltd.")),
        (CorrID.employer,      LText("Kontor Nordwind GmbH", "Kontor Nordwind Ltd."))
    ]

    static var correspondents: [Correspondent] {
        correspondentNames.map { Correspondent(id: $0.0, name: $0.1.text) }
    }

    private static let typeNames: [(Int, LText)] = [
        (TypeID.invoice,     LText("Rechnung", "Invoice")),
        (TypeID.contract,    LText("Vertrag", "Contract")),
        (TypeID.notice,      LText("Bescheid", "Official notice")),
        (TypeID.policy,      LText("Police", "Policy")),
        (TypeID.statement,   LText("Kontoauszug", "Bank statement")),
        (TypeID.payslip,     LText("Abrechnung", "Statement")),
        (TypeID.receipt,     LText("Quittung", "Receipt")),
        (TypeID.certificate, LText("Attest", "Medical certificate"))
    ]

    static var docTypes: [DocumentType] {
        typeNames.map { DocumentType(id: $0.0, name: $0.1.text) }
    }

    static var customFields: [CustomField] {
        [
            CustomField(id: FieldID.amount, name: LText("Betrag", "Amount").text, dataType: "monetary",
                        extraData: CustomField.ExtraData(selectOptions: nil, defaultCurrency: "EUR")),
            CustomField(id: FieldID.dueDate, name: LText("Fällig am", "Due date").text,
                        dataType: "date", extraData: nil),
            CustomField(id: FieldID.contractNo, name: LText("Vertragsnummer", "Contract no.").text,
                        dataType: "string", extraData: nil),
            CustomField(id: FieldID.paid, name: LText("Bezahlt", "Paid").text,
                        dataType: "boolean", extraData: nil)
        ]
    }

    // MARK: - Dokumente

    /// Ein Beispieldokument mit allem, was zum Rendern der PDF-Seite nötig ist.
    private struct Blueprint {
        let id: Int
        let title: LText
        let corr: Int?
        let type: Int?
        let tags: [Int]
        let asn: Int?
        /// Tage vor heute — hält die Liste bei jedem Start aktuell.
        let daysAgo: Int
        let subject: LText
        let body: [LText]
        var amount: LText? = nil
        var reference: LText? = nil
        var due: LText? = nil
        var fields: [CustomFieldEdit] = []
        var notes: [LText] = []
    }

    private static let blueprints: [Blueprint] = [
        Blueprint(
            id: 1042,
            title: LText("Stromabrechnung 2026", "Electricity statement 2026"),
            corr: CorrID.utilities, type: TypeID.invoice,
            tags: [TagID.invoice, TagID.home], asn: 231, daysAgo: 3,
            subject: LText("Jahresabrechnung Strom – Zählernummer 1188-4470",
                           "Annual electricity statement – meter no. 1188-4470"),
            body: [
                LText("Sehr geehrte Kundin, sehr geehrter Kunde,",
                      "Dear customer,"),
                LText("für den Abrechnungszeitraum vom 01.01.2026 bis 31.12.2026 haben wir Ihren Verbrauch abgelesen und abgerechnet. Der Zählerstand beträgt 24.118 kWh, das entspricht einem Jahresverbrauch von 2.640 kWh.",
                      "For the billing period from 1 January to 31 December 2026 we have read your meter and settled your account. The meter reading is 24,118 kWh, which corresponds to an annual consumption of 2,640 kWh."),
                LText("Ihr Abschlag lag bei 68,00 EUR monatlich. Daraus ergibt sich für das abgelaufene Jahr ein Guthaben, das wir Ihnen innerhalb von 14 Tagen auf das hinterlegte Konto überweisen.",
                      "Your monthly instalment was EUR 68.00. This leaves a credit for the past year, which we will transfer to your account within 14 days."),
                LText("Der neue monatliche Abschlag ab Februar beträgt 61,00 EUR. Eine Anpassung ist jederzeit über das Kundenportal möglich.",
                      "The new monthly instalment from February is EUR 61.00. You can adjust it at any time in the customer portal.")
            ],
            amount: LText("−142,60 EUR", "−142.60 EUR"),
            reference: LText("Kundennummer 40-118-2264", "Customer no. 40-118-2264"),
            fields: [
                CustomFieldEdit(field: FieldID.amount, value: .number(-142.60)),
                CustomFieldEdit(field: FieldID.contractNo, value: .text("40-118-2264")),
                CustomFieldEdit(field: FieldID.paid, value: .bool(true))
            ],
            notes: [LText("Guthaben ist am 12. auf dem Konto eingegangen.",
                          "Credit arrived in the account on the 12th.")]
        ),
        Blueprint(
            id: 1041,
            title: LText("Einkommensteuerbescheid 2025", "Income tax assessment 2025"),
            corr: CorrID.taxOffice, type: TypeID.notice,
            tags: [TagID.tax, TagID.important], asn: 230, daysAgo: 9,
            subject: LText("Bescheid für 2025 über Einkommensteuer und Solidaritätszuschlag",
                           "Assessment for 2025 – income tax and solidarity surcharge"),
            body: [
                LText("Die Festsetzung der Einkommensteuer für das Kalenderjahr 2025 erfolgt auf Grundlage der von Ihnen eingereichten Erklärung vom 14.03.2026.",
                      "Income tax for the 2025 calendar year has been assessed on the basis of the return you filed on 14 March 2026."),
                LText("Das zu versteuernde Einkommen beträgt 48.320,00 EUR. Nach Anrechnung der einbehaltenen Lohnsteuer ergibt sich ein Erstattungsanspruch.",
                      "Taxable income amounts to EUR 48,320.00. After crediting the wage tax already withheld, a refund is due to you."),
                LText("Die Erstattung wird auf das im Bescheid genannte Konto überwiesen. Der Bescheid ist mit dem Einspruch anfechtbar; die Frist beträgt einen Monat nach Bekanntgabe.",
                      "The refund will be transferred to the account named in this assessment. You may appeal within one month of notification.")
            ],
            amount: LText("Erstattung 612,00 EUR", "Refund 612.00 EUR"),
            reference: LText("Steuernummer 118/240/55019", "Tax number 118/240/55019"),
            fields: [
                CustomFieldEdit(field: FieldID.amount, value: .number(612.00)),
                CustomFieldEdit(field: FieldID.contractNo, value: .text("118/240/55019"))
            ],
            notes: [
                LText("Einspruchsfrist läuft bis Ende des Monats.", "Appeal deadline is the end of the month."),
                LText("Kopie an Steuerberatung geschickt.", "Copy sent to the tax adviser.")
            ]
        ),
        Blueprint(
            id: 1040,
            title: LText("Hausratversicherung Police", "Home contents policy"),
            corr: CorrID.nordlicht, type: TypeID.policy,
            tags: [TagID.insurance, TagID.home, TagID.important], asn: 229, daysAgo: 16,
            subject: LText("Versicherungsschein Hausrat – Vertrag HR-4471-09",
                           "Home contents certificate of insurance – policy HR-4471-09"),
            body: [
                LText("hiermit bestätigen wir den Versicherungsschutz für Ihren Hausrat ab dem 01.04.2026.",
                      "we hereby confirm cover for your home contents from 1 April 2026."),
                LText("Versicherungssumme: 65.000 EUR. Eingeschlossen sind Feuer, Leitungswasser, Sturm und Hagel sowie Einbruchdiebstahl. Fahrraddiebstahl ist bis 1.500 EUR mitversichert.",
                      "Sum insured: EUR 65,000. Cover includes fire, water damage, storm and hail as well as burglary. Bicycle theft is covered up to EUR 1,500."),
                LText("Der Jahresbeitrag wird jeweils zum 01.04. fällig und per Lastschrift eingezogen. Die Mindestvertragslaufzeit beträgt ein Jahr mit stillschweigender Verlängerung.",
                      "The annual premium is due on 1 April and collected by direct debit. The minimum term is one year and renews automatically.")
            ],
            amount: LText("184,20 EUR / Jahr", "184.20 EUR / year"),
            reference: LText("Vertrag HR-4471-09", "Policy HR-4471-09"),
            due: LText("01.04.2027", "1 April 2027"),
            fields: [
                CustomFieldEdit(field: FieldID.amount, value: .number(184.20)),
                CustomFieldEdit(field: FieldID.contractNo, value: .text("HR-4471-09")),
                CustomFieldEdit(field: FieldID.dueDate, value: .text("2027-04-01")),
                CustomFieldEdit(field: FieldID.paid, value: .bool(true))
            ]
        ),
        Blueprint(
            id: 1039,
            title: LText("Mobilfunkrechnung Februar", "Mobile bill February"),
            corr: CorrID.fonline, type: TypeID.invoice,
            tags: [TagID.invoice, TagID.contract], asn: 228, daysAgo: 22,
            subject: LText("Ihre Rechnung für den Abrechnungsmonat Februar",
                           "Your bill for the February billing period"),
            body: [
                LText("vielen Dank, dass Sie Fonline nutzen. Nachfolgend finden Sie die Abrechnung Ihres Tarifs Flex M.",
                      "thank you for choosing Fonline. Below is the statement for your Flex M plan."),
                LText("Grundpreis 24,99 EUR, Verbindungen außerhalb der Flatrate 0,00 EUR, Datenpaket 4,99 EUR. Alle Beträge verstehen sich inklusive Umsatzsteuer.",
                      "Base price EUR 24.99, calls outside the flat rate EUR 0.00, data package EUR 4.99. All amounts include VAT."),
                LText("Der Rechnungsbetrag wird zum genannten Termin von Ihrem Konto eingezogen. Eine detaillierte Verbindungsübersicht finden Sie im Kundenbereich.",
                      "The amount will be debited from your account on the date shown. A detailed call list is available in your customer area.")
            ],
            amount: LText("29,98 EUR", "29.98 EUR"),
            reference: LText("Kundenkonto 7723-0091", "Customer account 7723-0091"),
            due: LText("28.02.2026", "28 February 2026"),
            fields: [
                CustomFieldEdit(field: FieldID.amount, value: .number(29.98)),
                CustomFieldEdit(field: FieldID.dueDate, value: .text("2026-02-28")),
                CustomFieldEdit(field: FieldID.paid, value: .bool(true))
            ]
        ),
        Blueprint(
            id: 1038,
            title: LText("Mietvertrag Lindenweg 8", "Lease agreement Lindenweg 8"),
            corr: CorrID.lindenhof, type: TypeID.contract,
            tags: [TagID.home, TagID.contract, TagID.important], asn: 227, daysAgo: 34,
            subject: LText("Mietvertrag über Wohnraum – Lindenweg 8, 3. OG links",
                           "Residential lease – Lindenweg 8, third floor left"),
            body: [
                LText("Zwischen der Hausverwaltung Lindenhof als Vermieterin und der Mieterseite wird folgender Mietvertrag geschlossen.",
                      "The following lease is concluded between Lindenhof Property Management as landlord and the tenant."),
                LText("Mietgegenstand ist die Wohnung im 3. Obergeschoss links mit 74 m² Wohnfläche, bestehend aus drei Zimmern, Küche, Bad und Kellerabteil. Ein Stellplatz ist mitvermietet.",
                      "The let property is the third-floor left flat with 74 m² of living space, comprising three rooms, kitchen, bathroom and a cellar unit. One parking space is included."),
                LText("Die Grundmiete beträgt 890,00 EUR monatlich zuzüglich 210,00 EUR Betriebskostenvorauszahlung. Die Kaution beläuft sich auf drei Nettokaltmieten und wird auf ein Treuhandkonto eingezahlt.",
                      "The base rent is EUR 890.00 per month plus EUR 210.00 towards running costs. The deposit equals three months' base rent and is held in an escrow account."),
                LText("Das Mietverhältnis beginnt am 01.05.2026 und läuft auf unbestimmte Zeit.",
                      "The tenancy begins on 1 May 2026 and runs for an indefinite period.")
            ],
            amount: LText("1.100,00 EUR / Monat", "1,100.00 EUR / month"),
            reference: LText("Objekt L8-3L", "Unit L8-3L"),
            fields: [
                CustomFieldEdit(field: FieldID.amount, value: .number(1100.00)),
                CustomFieldEdit(field: FieldID.contractNo, value: .text("L8-3L"))
            ],
            notes: [LText("Kaution am 20.04. überwiesen.", "Deposit transferred on 20 April.")]
        ),
        Blueprint(
            id: 1037,
            title: LText("Nebenkostenabrechnung 2025", "Service charge statement 2025"),
            corr: CorrID.lindenhof, type: TypeID.payslip,
            tags: [TagID.home, TagID.utilities], asn: 226, daysAgo: 41,
            subject: LText("Betriebskostenabrechnung für den Zeitraum 01.01.2025 – 31.12.2025",
                           "Service charge statement for 1 January – 31 December 2025"),
            body: [
                LText("anbei erhalten Sie die Abrechnung der Betriebskosten für das vergangene Kalenderjahr.",
                      "please find enclosed the service charge statement for the past calendar year."),
                LText("Umlagefähig sind Grundsteuer, Wasser und Abwasser, Müllabfuhr, Hausreinigung, Gartenpflege, Beleuchtung, Aufzug sowie die Sach- und Haftpflichtversicherung des Gebäudes.",
                      "Recoverable items are property tax, water and sewage, refuse collection, cleaning, gardening, lighting, the lift, and the building's property and liability insurance."),
                LText("Ihre Vorauszahlungen betrugen 2.520,00 EUR, die tatsächlichen Kosten 2.386,40 EUR. Der Differenzbetrag wird mit der nächsten Mietzahlung verrechnet.",
                      "Your advance payments came to EUR 2,520.00, actual costs to EUR 2,386.40. The difference will be offset against your next rent payment.")
            ],
            amount: LText("−133,60 EUR", "−133.60 EUR"),
            reference: LText("Objekt L8-3L", "Unit L8-3L"),
            fields: [CustomFieldEdit(field: FieldID.amount, value: .number(-133.60))]
        ),
        Blueprint(
            id: 1036,
            title: LText("Inspektion und Ölwechsel", "Service and oil change"),
            corr: CorrID.garage, type: TypeID.invoice,
            tags: [TagID.car, TagID.invoice], asn: 225, daysAgo: 55,
            subject: LText("Rechnung Werkstattauftrag 2026-0338", "Invoice for repair order 2026-0338"),
            body: [
                LText("wir haben an Ihrem Fahrzeug die turnusmäßige Inspektion durchgeführt.",
                      "we have carried out the scheduled service on your vehicle."),
                LText("Ausgeführte Arbeiten: Motoröl und Ölfilter erneuert, Luftfilter gewechselt, Bremsanlage geprüft, Reifendruck korrigiert, Fehlerspeicher ausgelesen — ohne Befund.",
                      "Work performed: engine oil and oil filter replaced, air filter changed, brake system inspected, tyre pressures corrected, fault memory read — no issues found."),
                LText("Hinweis: Die vorderen Bremsbeläge liegen bei etwa 30 % Restbelag. Eine Erneuerung empfehlen wir zum nächsten Termin.",
                      "Please note: the front brake pads are down to roughly 30 % of their lining. We recommend replacing them at your next appointment."),
                LText("Die nächste Hauptuntersuchung ist im November fällig.",
                      "The next roadworthiness test is due in November.")
            ],
            amount: LText("318,45 EUR", "318.45 EUR"),
            reference: LText("Auftrag 2026-0338", "Order 2026-0338"),
            due: LText("10.03.2026", "10 March 2026"),
            fields: [
                CustomFieldEdit(field: FieldID.amount, value: .number(318.45)),
                CustomFieldEdit(field: FieldID.dueDate, value: .text("2026-03-10")),
                CustomFieldEdit(field: FieldID.paid, value: .bool(true))
            ],
            notes: [LText("Bremsbeläge beim nächsten Termin einplanen.",
                          "Schedule brake pads for the next appointment.")]
        ),
        Blueprint(
            id: 1035,
            title: LText("Zahnarztrechnung Kontrolle", "Dental check-up invoice"),
            corr: CorrID.dentist, type: TypeID.invoice,
            tags: [TagID.health, TagID.invoice], asn: 224, daysAgo: 62,
            subject: LText("Liquidation für zahnärztliche Leistungen", "Invoice for dental services"),
            body: [
                LText("für die durchgeführte Behandlung erlauben wir uns, folgende Leistungen zu berechnen.",
                      "for the treatment provided we are pleased to invoice the following services."),
                LText("Eingehende Untersuchung, Erhebung des Parodontalstatus, professionelle Zahnreinigung sowie eine Fluoridierung. Die Abrechnung erfolgt nach der Gebührenordnung für Zahnärzte.",
                      "Thorough examination, periodontal assessment, professional cleaning and fluoride treatment. Billed according to the dental fee schedule."),
                LText("Bitte reichen Sie den Beleg bei Ihrer Krankenkasse zur Erstattung ein. Zahlbar innerhalb von 30 Tagen ohne Abzug.",
                      "Please submit this invoice to your health insurer for reimbursement. Payable within 30 days without deduction.")
            ],
            amount: LText("128,90 EUR", "128.90 EUR"),
            reference: LText("Rechnung 26-0774", "Invoice 26-0774"),
            due: LText("05.03.2026", "5 March 2026"),
            fields: [
                CustomFieldEdit(field: FieldID.amount, value: .number(128.90)),
                CustomFieldEdit(field: FieldID.dueDate, value: .text("2026-03-05")),
                CustomFieldEdit(field: FieldID.paid, value: .bool(false))
            ]
        ),
        Blueprint(
            id: 1034,
            title: LText("Erstattung Zahnreinigung", "Reimbursement dental cleaning"),
            corr: CorrID.healthInsurer, type: TypeID.notice,
            tags: [TagID.health], asn: 223, daysAgo: 68,
            subject: LText("Ihre Erstattung – Vorgang 88-2261", "Your reimbursement – case 88-2261"),
            body: [
                LText("wir haben Ihren eingereichten Beleg geprüft und erstatten anteilig im Rahmen Ihres Bonusprogramms.",
                      "we have reviewed the receipt you submitted and will reimburse part of it under your bonus programme."),
                LText("Erstattet werden 80 % der Kosten für die professionelle Zahnreinigung, höchstens jedoch 100,00 EUR je Kalenderjahr.",
                      "We reimburse 80 % of the cost of professional dental cleaning, up to EUR 100.00 per calendar year."),
                LText("Der Betrag wird in den nächsten Tagen auf Ihr Konto überwiesen. Weitere Belege können Sie bequem über die Servicekarte einreichen.",
                      "The amount will be transferred to your account in the next few days. You can submit further receipts through your service card.")
            ],
            amount: LText("100,00 EUR", "100.00 EUR"),
            reference: LText("Vorgang 88-2261", "Case 88-2261"),
            fields: [CustomFieldEdit(field: FieldID.amount, value: .number(100.00))]
        ),
        Blueprint(
            id: 1033,
            title: LText("Gehaltsabrechnung Januar", "Payslip January"),
            corr: CorrID.employer, type: TypeID.payslip,
            tags: [TagID.work, TagID.important], asn: 222, daysAgo: 74,
            subject: LText("Entgeltabrechnung für den Abrechnungsmonat Januar",
                           "Statement of earnings for the January pay period"),
            body: [
                LText("nachfolgend erhalten Sie Ihre Abrechnung der Brutto- und Nettobezüge.",
                      "below you will find the statement of your gross and net pay."),
                LText("Bruttoentgelt 4.150,00 EUR, davon Lohnsteuer, Solidaritätszuschlag sowie Beiträge zur Kranken-, Pflege-, Renten- und Arbeitslosenversicherung.",
                      "Gross pay EUR 4,150.00, less wage tax, solidarity surcharge and contributions to health, long-term care, pension and unemployment insurance."),
                LText("Die vermögenswirksamen Leistungen in Höhe von 40,00 EUR werden direkt an den Vertragspartner überwiesen. Die Auszahlung des Nettobetrags erfolgt zum Monatsende.",
                      "The capital-forming benefit of EUR 40.00 is paid directly to the contract partner. The net amount is paid out at the end of the month.")
            ],
            amount: LText("2.612,88 EUR netto", "2,612.88 EUR net"),
            reference: LText("Personalnummer 3391", "Employee no. 3391"),
            fields: [
                CustomFieldEdit(field: FieldID.amount, value: .number(2612.88)),
                CustomFieldEdit(field: FieldID.contractNo, value: .text("PN-3391"))
            ]
        ),
        Blueprint(
            id: 1032,
            title: LText("Kontoauszug Januar", "Bank statement January"),
            corr: CorrID.bank, type: TypeID.statement,
            tags: [TagID.bank], asn: 221, daysAgo: 80,
            subject: LText("Kontoauszug Nr. 1 – Girokonto", "Statement no. 1 – current account"),
            body: [
                LText("Auszug für den Zeitraum 01.01.2026 bis 31.01.2026.",
                      "Statement for the period 1 January to 31 January 2026."),
                LText("Alter Kontostand 3.184,22 EUR. Gutschriften 2.652,88 EUR, Lastschriften und Überweisungen 2.104,31 EUR.",
                      "Opening balance EUR 3,184.22. Credits EUR 2,652.88, direct debits and transfers EUR 2,104.31."),
                LText("Neuer Kontostand 3.732,79 EUR. Bitte prüfen Sie die Buchungen. Einwendungen gegen Lastschriften sind innerhalb von acht Wochen möglich.",
                      "Closing balance EUR 3,732.79. Please check the entries. Direct debits may be disputed within eight weeks.")
            ],
            amount: LText("3.732,79 EUR", "3,732.79 EUR"),
            reference: LText("Konto DE00 0000 0000 0000 0000 00", "Account DE00 0000 0000 0000 0000 00")
        ),
        Blueprint(
            id: 1031,
            title: LText("Kaufbeleg Waschmaschine", "Receipt washing machine"),
            corr: CorrID.electronics, type: TypeID.receipt,
            tags: [TagID.warranty, TagID.important], asn: 220, daysAgo: 96,
            subject: LText("Kaufbeleg und Garantieurkunde", "Proof of purchase and warranty certificate"),
            body: [
                LText("vielen Dank für Ihren Einkauf. Dieser Beleg gilt zusammen mit der Garantieurkunde als Nachweis.",
                      "thank you for your purchase. Together with the warranty certificate, this receipt serves as proof."),
                LText("Artikel: Waschmaschine Frontlader, 8 kg, Energieeffizienzklasse A. Seriennummer WM-0099-4471.",
                      "Item: front-loading washing machine, 8 kg, energy class A. Serial number WM-0099-4471."),
                LText("Die gesetzliche Gewährleistung beträgt 24 Monate. Zusätzlich gewähren wir eine Herstellergarantie von 36 Monaten ab Kaufdatum. Bewahren Sie diesen Beleg gut auf.",
                      "The statutory warranty period is 24 months. In addition we grant a manufacturer's warranty of 36 months from the date of purchase. Please keep this receipt safe.")
            ],
            amount: LText("649,00 EUR", "649.00 EUR"),
            reference: LText("Beleg 2026-11884", "Receipt 2026-11884"),
            fields: [
                CustomFieldEdit(field: FieldID.amount, value: .number(649.00)),
                CustomFieldEdit(field: FieldID.dueDate, value: .text("2029-01-14")),
                CustomFieldEdit(field: FieldID.paid, value: .bool(true))
            ],
            notes: [LText("Garantie läuft bis Januar 2029.", "Warranty runs until January 2029.")]
        ),
        Blueprint(
            id: 1030,
            title: LText("Kfz-Versicherung Beitragsrechnung", "Car insurance premium notice"),
            corr: CorrID.nordlicht, type: TypeID.invoice,
            tags: [TagID.car, TagID.insurance, TagID.invoice], asn: 219, daysAgo: 112,
            subject: LText("Beitragsrechnung Kfz-Haftpflicht und Teilkasko",
                           "Premium notice – third-party liability and partial comprehensive"),
            body: [
                LText("für das kommende Versicherungsjahr berechnen wir den Beitrag wie folgt.",
                      "for the coming insurance year we calculate your premium as follows."),
                LText("Kfz-Haftpflicht mit Schadenfreiheitsklasse SF 12, Teilkasko mit 150 EUR Selbstbeteiligung. Die jährliche Fahrleistung ist mit 12.000 km hinterlegt.",
                      "Third-party liability at no-claims class SF 12, partial comprehensive with a EUR 150 excess. Annual mileage on file is 12,000 km."),
                LText("Änderungen an Fahrleistung oder Nutzerkreis melden Sie bitte vorab, damit der Beitrag korrekt bleibt.",
                      "Please report any change in mileage or drivers in advance so the premium stays correct.")
            ],
            amount: LText("412,00 EUR / Jahr", "412.00 EUR / year"),
            reference: LText("Vertrag KH-8830-21", "Policy KH-8830-21"),
            due: LText("01.01.2027", "1 January 2027"),
            fields: [
                CustomFieldEdit(field: FieldID.amount, value: .number(412.00)),
                CustomFieldEdit(field: FieldID.contractNo, value: .text("KH-8830-21")),
                CustomFieldEdit(field: FieldID.dueDate, value: .text("2027-01-01"))
            ]
        ),
        Blueprint(
            id: 1029,
            title: LText("Internetvertrag Glasfaser", "Fibre internet contract"),
            corr: CorrID.fonline, type: TypeID.contract,
            tags: [TagID.contract, TagID.home], asn: 218, daysAgo: 138,
            subject: LText("Auftragsbestätigung Glasfaseranschluss 500",
                           "Order confirmation – Fibre 500 connection"),
            body: [
                LText("wir bestätigen den Abschluss Ihres Vertrags über einen Glasfaseranschluss.",
                      "we confirm your contract for a fibre-optic connection."),
                LText("Gebuchte Leistung: 500 Mbit/s Download, 100 Mbit/s Upload, Telefonie-Flatrate ins deutsche Festnetz, Router zur Miete.",
                      "Booked service: 500 Mbit/s download, 100 Mbit/s upload, landline flat rate, router included on rental."),
                LText("Der Anschluss wird zum genannten Termin geschaltet. Die Mindestlaufzeit beträgt 24 Monate, die Kündigungsfrist einen Monat zum Laufzeitende.",
                      "The line will be activated on the date given. The minimum term is 24 months with one month's notice to the end of the term.")
            ],
            amount: LText("44,99 EUR / Monat", "44.99 EUR / month"),
            reference: LText("Auftrag GF-55219", "Order GF-55219"),
            fields: [
                CustomFieldEdit(field: FieldID.amount, value: .number(44.99)),
                CustomFieldEdit(field: FieldID.contractNo, value: .text("GF-55219"))
            ]
        ),
        Blueprint(
            id: 1028,
            title: LText("Lieferschein Bürostuhl", "Delivery note office chair"),
            corr: CorrID.mailOrder, type: TypeID.receipt,
            tags: [TagID.warranty], asn: 217, daysAgo: 165,
            subject: LText("Lieferschein zur Bestellung 990-4471-22",
                           "Delivery note for order 990-4471-22"),
            body: [
                LText("Ihre Bestellung wurde versandt. Dieser Lieferschein dient als Nachweis über den Umfang der Lieferung.",
                      "Your order has been dispatched. This delivery note documents the scope of the shipment."),
                LText("Position 1: Bürodrehstuhl, ergonomisch, mit Lordosenstütze und Armlehnen, Farbe anthrazit. Menge 1.",
                      "Item 1: ergonomic office swivel chair with lumbar support and armrests, anthracite. Quantity 1."),
                LText("Das Rückgaberecht beträgt 30 Tage ab Zustellung. Die Originalverpackung ist dafür nicht erforderlich.",
                      "You may return the item within 30 days of delivery. The original packaging is not required.")
            ],
            amount: LText("289,00 EUR", "289.00 EUR"),
            reference: LText("Bestellung 990-4471-22", "Order 990-4471-22")
        ),
        // Ohne Absender → landen im Posteingang und geben dem Tab sein Badge.
        Blueprint(
            id: 1027, title: LText("Scan {date}", "Scan {date}"),
            corr: nil, type: nil, tags: [], asn: nil, daysAgo: 1,
            subject: LText("Eingescanntes Dokument – noch nicht zugeordnet",
                           "Scanned document – not yet filed"),
            body: [
                LText("Dieses Dokument wurde gerade erfasst und wartet auf Titel, Absender und Tags.",
                      "This document has just been captured and is waiting for a title, correspondent and tags."),
                LText("Der Zauberstab schlägt die Metadaten anhand des erkannten Textes vor — ein Tipp genügt, um Titel, Absender, Typ und Tags zu übernehmen. Fehlende Sender, Typen und Tags legt die App dabei gleich mit an.",
                      "The magic wand suggests metadata from the recognised text — one tap fills in title, correspondent, type and tags. Missing correspondents, types and tags are created along the way."),
                LText("Bis dahin bleibt das Dokument im Posteingang und zählt im Abzeichen des Tabs mit.",
                      "Until then the document stays in the inbox and counts towards the tab badge.")
            ],
            reference: LText("Erfasst mit der Kamera", "Captured with the camera")
        ),
        Blueprint(
            id: 1026, title: LText("Scan {date}", "Scan {date}"),
            corr: nil, type: nil, tags: [TagID.invoice], asn: nil, daysAgo: 2,
            subject: LText("Eingescanntes Dokument – Absender fehlt noch",
                           "Scanned document – correspondent still missing"),
            body: [
                LText("Beleg über eine Anschaffung. Der Betrag und das Datum wurden bereits erkannt, der Absender fehlt noch.",
                      "Receipt for a purchase. The amount and date were recognised, the correspondent is still missing."),
                LText("Über Wischen nach links lässt sich direkt ein Tag setzen, ohne das Dokument überhaupt zu öffnen. Wischen nach rechts öffnet die Bearbeitung.",
                      "Swipe left to assign a tag without even opening the document. Swipe right opens the editor."),
                LText("Die Volltextsuche findet den Beleg auch dann, wenn nur ein Wort aus dem erkannten Text erinnert wird.",
                      "Full-text search finds the receipt even when only one word from the recognised text is remembered.")
            ],
            reference: LText("Aus der Fotomediathek", "From the photo library")
        ),
        Blueprint(
            id: 1025, title: LText("Scan {date}", "Scan {date}"),
            corr: nil, type: nil, tags: [], asn: nil, daysAgo: 4,
            subject: LText("Eingescanntes Dokument – Posteingang", "Scanned document – inbox"),
            body: [
                LText("Mehrseitiger Stapel-Scan. Die Seitentrennung wurde automatisch anhand der Briefköpfe vorgeschlagen.",
                      "Multi-page batch scan. Page splits were suggested automatically from the letterheads."),
                LText("Falsche Trennungen lassen sich vor dem Hochladen mit einem Stepper korrigieren, ohne den Stapel neu einzulesen.",
                      "Incorrect splits can be corrected with a stepper before uploading, without rescanning the stack."),
                LText("Anschließend wandert jede Gruppe als eigenes Dokument ins Archiv.",
                      "Each group then goes into the archive as its own document.")
            ],
            reference: LText("Stapel-Scan, Seite 1 von 3", "Batch scan, page 1 of 3")
        )
    ]

    // MARK: - Aufbau

    static func makeContent() -> Content {
        let documents = blueprints.map { bp -> Document in
            Document(
                id: bp.id,
                title: title(for: bp),
                content: ocrText(for: bp),
                created: dateString(daysAgo: bp.daysAgo),
                added: dateString(daysAgo: max(0, bp.daysAgo - 1)),
                correspondent: bp.corr,
                documentType: bp.type,
                archiveSerialNumber: bp.asn,
                tags: bp.tags,
                notes: notes(for: bp),
                customFields: bp.fields
            )
        }

        let characters = documents.reduce(0) { $0 + ($1.content?.count ?? 0) }
        let stats = PaperlessStatistics(
            documentsTotal: documents.count,
            documentsInbox: documents.filter { $0.correspondent == nil }.count,
            characterCount: characters
        )

        return Content(tags: tags, correspondents: correspondents, docTypes: docTypes,
                       customFields: customFields, documents: documents, statistics: stats)
    }

    /// Schreibt zu jedem Beispieldokument ein PDF in den Dokument-Cache des Kontos und
    /// legt die passende Miniaturansicht im `ImageCache` ab.
    static func materialize(accountId: UUID) {
        for bp in blueprints {
            let url = PersistenceService.docFileURL(for: bp.id, accountId: accountId)
            guard let data = renderPDF(for: bp) else { continue }
            try? data.write(to: url)

            if let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) {
                let thumb = page.thumbnail(of: CGSize(width: 420, height: 594), for: .mediaBox)
                ImageCache.shared.saveImage(thumb, for: bp.id)
            }
        }
    }

    // MARK: - Text

    /// `{date}` im Titel wird durch das Dokumentdatum ersetzt — so passen die Titel der
    /// frischen Scans immer zu den Datumsangaben in der Liste.
    private static func title(for bp: Blueprint) -> String {
        bp.title.text.replacingOccurrences(of: "{date}", with: dateString(daysAgo: bp.daysAgo))
    }

    private static func ocrText(for bp: Blueprint) -> String {
        var lines: [String] = []
        if let corr = bp.corr, let name = correspondentNames.first(where: { $0.0 == corr })?.1.text {
            lines.append(name)
        }
        lines.append(bp.subject.text)
        lines.append(contentsOf: bp.body.map(\.text))
        if let reference = bp.reference { lines.append(reference.text) }
        if let amount = bp.amount {
            lines.append(LText("Betrag: \(amount.de)", "Amount: \(amount.en)").text)
        }
        if let due = bp.due {
            lines.append(LText("Fällig am: \(due.de)", "Due: \(due.en)").text)
        }
        return lines.joined(separator: "\n\n")
    }

    private static func notes(for bp: Blueprint) -> [Note]? {
        guard !bp.notes.isEmpty else { return nil }
        return bp.notes.enumerated().map { index, text in
            Note(id: bp.id * 10 + index, note: text.text,
                 created: dateString(daysAgo: max(0, bp.daysAgo - 2)), user: 1)
        }
    }

    private static func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    private static func displayDate(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let df = DateFormatter()
        df.locale = Locale(identifier: usesEnglish ? "en_GB" : "de_DE")
        df.dateFormat = usesEnglish ? "d MMMM yyyy" : "dd.MM.yyyy"
        return df.string(from: date)
    }

    // MARK: - PDF-Seite

    /// A4 in Punkt.
    private static let pageSize = CGSize(width: 595, height: 842)

    private static func renderPDF(for bp: Blueprint) -> Data? {
        let margin: CGFloat = 56
        let contentWidth = pageSize.width - margin * 2
        let accent = accentColor(for: bp)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            UIColor.white.setFill()
            ctx.cgContext.fill(CGRect(origin: .zero, size: pageSize))

            var y: CGFloat = margin

            // Briefkopf: farbiger Balken plus Absendername.
            accent.setFill()
            ctx.cgContext.fill(CGRect(x: margin, y: y, width: 46, height: 6))
            y += 18

            let senderName = bp.corr.flatMap { id in correspondentNames.first { $0.0 == id }?.1.text }
                ?? LText("Ohne Absender", "No correspondent").text
            y = draw(senderName, at: CGPoint(x: margin, y: y), width: contentWidth,
                     font: .systemFont(ofSize: 17, weight: .bold), color: accent)
            y = draw("Musterallee 4 · 12345 Musterstadt · service@example.invalid",
                     at: CGPoint(x: margin, y: y + 2), width: contentWidth,
                     font: .systemFont(ofSize: 8), color: .darkGray)

            y += 34

            // Empfängerblock links, Datum rechts.
            let recipientY = y
            y = draw(LText("Max Mustermann\nMusterstraße 12\n12345 Musterstadt",
                           "Alex Sample\n12 Sample Street\n12345 Sampleton").text,
                     at: CGPoint(x: margin, y: y), width: 260,
                     font: .systemFont(ofSize: 10), color: .black, lineSpacing: 3)

            let place = LText("Musterstadt, \(displayDate(daysAgo: bp.daysAgo))",
                              "Sampleton, \(displayDate(daysAgo: bp.daysAgo))").text
            _ = draw(place, at: CGPoint(x: margin + contentWidth - 200, y: recipientY), width: 200,
                     font: .systemFont(ofSize: 10), color: .darkGray, alignment: .right)

            y += 34

            y = draw(bp.subject.text, at: CGPoint(x: margin, y: y), width: contentWidth,
                     font: .systemFont(ofSize: 12, weight: .semibold), color: .black, lineSpacing: 3)
            y += 16

            for paragraph in bp.body {
                y = draw(paragraph.text, at: CGPoint(x: margin, y: y), width: contentWidth,
                         font: .systemFont(ofSize: 10), color: UIColor(white: 0.15, alpha: 1), lineSpacing: 4)
                y += 12
                if y > pageSize.height - 190 { break }
            }

            // Eckdaten-Kasten.
            var boxRows: [(String, String)] = []
            if let reference = bp.reference {
                boxRows.append((LText("Referenz", "Reference").text, reference.text))
            }
            if let amount = bp.amount {
                boxRows.append((LText("Betrag", "Amount").text, amount.text))
            }
            if let due = bp.due {
                boxRows.append((LText("Fällig am", "Due date").text, due.text))
            }
            if let asn = bp.asn {
                boxRows.append((LText("Archiv-Nr.", "Archive no.").text, "ASN \(asn)"))
            }

            if !boxRows.isEmpty {
                y += 8
                let boxHeight = CGFloat(boxRows.count) * 20 + 20
                let box = CGRect(x: margin, y: y, width: contentWidth, height: boxHeight)
                accent.withAlphaComponent(0.07).setFill()
                UIBezierPath(roundedRect: box, cornerRadius: 8).fill()

                var rowY = y + 10
                for (label, value) in boxRows {
                    _ = draw(label, at: CGPoint(x: margin + 14, y: rowY), width: 130,
                             font: .systemFont(ofSize: 9.5), color: .darkGray)
                    _ = draw(value, at: CGPoint(x: margin + 150, y: rowY), width: contentWidth - 164,
                             font: .systemFont(ofSize: 9.5, weight: .semibold), color: .black)
                    rowY += 20
                }
                y += boxHeight
            }

            // Fußzeile.
            let footerY = pageSize.height - margin - 24
            UIColor(white: 0.85, alpha: 1).setFill()
            ctx.cgContext.fill(CGRect(x: margin, y: footerY, width: contentWidth, height: 0.6))
            _ = draw(LText("Beispieldokument · Demo-Modus von Paperless 24 · keine echten Daten",
                           "Sample document · Paperless 24 demo mode · no real data").text,
                     at: CGPoint(x: margin, y: footerY + 8), width: contentWidth,
                     font: .systemFont(ofSize: 8), color: .gray)
        }
    }

    private static func accentColor(for bp: Blueprint) -> UIColor {
        let indigo = UIColor(red: 0.25, green: 0.31, blue: 0.71, alpha: 1)
        guard let firstTag = bp.tags.first,
              let hex = tagNames.first(where: { $0.0 == firstTag })?.2 else { return indigo }
        return UIColor(hexString: hex) ?? indigo
    }

    /// Zeichnet umbrochenen Text und gibt die Unterkante zurück.
    @discardableResult
    private static func draw(_ text: String, at point: CGPoint, width: CGFloat,
                             font: UIFont, color: UIColor,
                             lineSpacing: CGFloat = 0,
                             alignment: NSTextAlignment = .left) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: style
        ]
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes, context: nil
        )
        (text as NSString).draw(with: CGRect(x: point.x, y: point.y, width: width, height: ceil(bounding.height)),
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: attributes, context: nil)
        return point.y + ceil(bounding.height)
    }
}

private extension UIColor {
    /// Hex mit oder ohne führendes `#`.
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
