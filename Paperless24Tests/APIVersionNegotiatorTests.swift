import Testing
import Foundation
@testable import Paperless24

/// Deckt die API-Versionsaushandlung ab, mit der die App gleichzeitig zu
/// paperless-ngx 3.0 (nur noch Version 9 und 10 erlaubt) und zu älteren
/// Servern kompatibel bleibt.
struct APIVersionNegotiatorTests {

    /// Eigener Server-Key je Test, damit sich die in UserDefaults gemerkten
    /// Modi zwischen den Tests nicht überlagern.
    private func makeServer() -> String { "https://test-\(UUID().uuidString).example" }

    private func response(apiVersion: String?) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example/api/documents/")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: apiVersion.map { ["X-Api-Version": $0] }
        )!
    }

    @Test func unbekannterServerBekommtBevorzugteVersion() {
        let server = makeServer()
        #expect(APIVersionNegotiator.version(for: server) == APIVersionNegotiator.preferred)
    }

    @Test func serverMitNeuererApiBleibtAufBevorzugterVersion() {
        let server = makeServer()
        // ngx 3.0.x meldet 10, erlaubt aber weiterhin 9.
        APIVersionNegotiator.record(response: response(apiVersion: "10"), server: server)
        #expect(APIVersionNegotiator.version(for: server) == 9)
    }

    @Test func alterServerBekommtKeinenVersionHeader() {
        let server = makeServer()
        // ngx <= 2.13 kann höchstens 5.
        APIVersionNegotiator.record(response: response(apiVersion: "5"), server: server)
        #expect(APIVersionNegotiator.version(for: server) == nil)
    }

    @Test func vierhundertsechsSchaltetDauerhaftAufServerDefault() {
        let server = makeServer()
        APIVersionNegotiator.fallbackToServerDefault(server: server)
        #expect(APIVersionNegotiator.version(for: server) == nil)
    }

    @Test func fehlenderHeaderAendertNichts() {
        let server = makeServer()
        APIVersionNegotiator.record(response: response(apiVersion: nil), server: server)
        #expect(APIVersionNegotiator.version(for: server) == APIVersionNegotiator.preferred)
    }

    /// Ein 406 ist bindend: ein Server, der 9 abgelehnt hat, aber ein höheres Maximum
    /// meldet, darf nicht wieder auf 9 hochgestuft werden — sonst 406 und Retry im Dauerlauf.
    @Test func ablehnungUeberlebtSpaeterenHeader() {
        let server = makeServer()
        APIVersionNegotiator.fallbackToServerDefault(server: server)
        APIVersionNegotiator.record(response: response(apiVersion: "11"), server: server)
        #expect(APIVersionNegotiator.version(for: server) == nil)
    }
}
