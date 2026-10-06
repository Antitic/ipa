import Foundation

/// Le compte Pin (adresse @dipherant.xyz). Nécessaire pour WhatsApp et Musique ;
/// Photos et Claude marchent sans.
@MainActor
final class Compte: ObservableObject {
    @Published private(set) var email: String?
    @Published private(set) var verifie = false

    var connecte: Bool { email != nil }

    private struct Moi: Decodable { let id: String; let email: String }

    func verifier() async {
        do {
            let moi = try await API.get("/api/auth/me", Moi.self)
            email = moi.email
        } catch let e as ErreurPin where e.statut == 401 {
            email = nil
        } catch {
            // Hors ligne : on garde l'état précédent.
        }
        verifie = true
    }

    func connexion(email: String, motDePasse: String) async throws {
        let moi = try await API.post("/api/auth/login", ["email": email, "password": motDePasse], Moi.self)
        self.email = moi.email
    }

    func deconnexion() async {
        _ = try? await API.requete("/api/auth/logout", methode: "POST", json: [:])
        email = nil
    }
}
