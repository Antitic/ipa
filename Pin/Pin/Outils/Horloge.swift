import SwiftUI
import UserNotifications
import AudioToolbox

struct MenuHorloge: View {
    @EnvironmentObject var nav: Navigateur
    @ObservedObject private var minuteur = Minuteur.partage
    var body: some View {
        EcranListe(cle: .horloge, elements: [
            ElementListe(id: "chrono", titre: "Chronomètre"),
            ElementListe(id: "minuteur", titre: "Minuteur", detail: minuteur.enCours ? "En cours · " + Minuteur.format(minuteur.restant) : nil),
        ]) { e in nav.ouvrir(e.id == "chrono" ? .chrono : .minuteur) }
    }
}

// MARK: - Chronomètre

@MainActor
final class Chrono: ObservableObject {
    static let partage = Chrono()
    @Published private(set) var debut: Date?
    @Published private(set) var cumul: TimeInterval = 0
    @Published private(set) var tours: [TimeInterval] = []

    var enMarche: Bool { debut != nil }
    func ecoule(_ maintenant: Date = Date()) -> TimeInterval { cumul + (debut.map { maintenant.timeIntervalSince($0) } ?? 0) }

    func basculer() {
        if let d = debut { cumul += Date().timeIntervalSince(d); debut = nil } else { debut = Date() }
    }
    func tour() { if enMarche { tours.insert(ecoule(), at: 0) } }
    func remettre() { guard !enMarche else { return }; cumul = 0; tours = [] }

    static func format(_ t: TimeInterval) -> String {
        let cs = Int((t * 100).rounded(.down))
        return String(format: "%02d:%02d,%02d", cs / 6000, (cs / 100) % 60, cs % 100)
    }
}

struct EcranChrono: View {
    @ObservedObject private var chrono = Chrono.partage

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 0.03, paused: !chrono.enMarche)) { c in
                Text(Chrono.format(chrono.ecoule(c.date)))
                    .font(.system(size: 40, weight: .light).monospacedDigit())
            }
            .padding(.top, 10)
            Text(chrono.enMarche ? "Centre : pause · ⏭ : tour" : (chrono.ecoule() > 0 ? "Centre : reprendre · ⏮ : remettre à zéro" : "Centre : démarrer"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(chrono.tours.enumerated()), id: \.offset) { i, t in
                        let suivant = i + 1 < chrono.tours.count ? chrono.tours[i + 1] : 0
                        HStack {
                            Text("Tour \(chrono.tours.count - i)").font(.system(size: 12))
                            Spacer()
                            Text("+" + Chrono.format(t - suivant)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                            Text(Chrono.format(t)).font(.system(size: 12, weight: .medium).monospacedDigit())
                        }
                        .padding(.horizontal, 12).frame(height: 24)
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .roue { g in
            g.centre = { chrono.basculer() }
            g.suivant = { chrono.tour() }
            g.precedent = { chrono.remettre() }
        }
    }
}

// MARK: - Minuteur

@MainActor
final class Minuteur: ObservableObject {
    static let partage = Minuteur()
    @Published var duree: TimeInterval = 5 * 60
    @Published private(set) var fin: Date?
    @Published private(set) var enPause: TimeInterval?
    @Published private(set) var sonne = false
    @Published private(set) var restant: TimeInterval = 0
    private var boucle: Task<Void, Never>?

    var enCours: Bool { fin != nil || enPause != nil }

    func regler(_ crans: Int) {
        guard !enCours else { return }
        let pas: TimeInterval = duree < 60 ? 5 : (duree < 600 ? 30 : 60)
        duree = min(max(duree + Double(crans) * pas, 5), 12 * 3600)
    }

    func centre() {
        if sonne { sonne = false; return }
        if let f = fin {
            enPause = f.timeIntervalSinceNow
            fin = nil
            boucle?.cancel()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        } else {
            let d = enPause ?? duree
            enPause = nil
            fin = Date().addingTimeInterval(d)
            programmerNotification(d)
            demarrer()
        }
    }

    func annuler() {
        fin = nil; enPause = nil; sonne = false; boucle?.cancel()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func demarrer() {
        boucle?.cancel()
        boucle = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let f = self.fin else { return }
                self.restant = max(0, f.timeIntervalSinceNow)
                if self.restant <= 0 {
                    self.fin = nil
                    self.sonne = true
                    self.sonner()
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func sonner() {
        Task { @MainActor in
            for _ in 0..<6 where sonne {
                AudioServicesPlayAlertSound(SystemSoundID(1005))
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                try? await Task.sleep(for: .seconds(1.2))
            }
        }
    }

    /// Pour être prévenu même si Pin est en arrière-plan.
    private func programmerNotification(_ d: TimeInterval) {
        let centre = UNUserNotificationCenter.current()
        centre.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = "Minuteur"
            c.body = "Temps écoulé ⏰"
            c.sound = .default
            centre.add(UNNotificationRequest(identifier: "pin.minuteur", content: c,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, d), repeats: false)))
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

struct EcranMinuteur: View {
    @ObservedObject private var m = Minuteur.partage

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color(white: 0.88), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: m.enCours ? CGFloat((m.enPause ?? m.restant) / max(m.duree, 1)) : 1)
                    .stroke(m.sonne ? Color.red : Color(red: 0.16, green: 0.44, blue: 0.86), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: m.restant)
                Text(m.sonne ? "Terminé" : Minuteur.format(m.enCours ? (m.enPause ?? m.restant) : m.duree))
                    .font(.system(size: 30, weight: .light).monospacedDigit())
            }
            .frame(width: 150, height: 150)
            .padding(.top, 10)
            Text(m.sonne ? "Centre : arrêter" : (m.enCours ? (m.enPause != nil ? "Centre : reprendre · ⏮ : annuler" : "Centre : pause · ⏮ : annuler") : "Molette : durée · Centre : démarrer"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .roue { g in
            g.tour = { s in m.regler(s) }
            g.centre = { m.centre() }
            g.precedent = { m.annuler() }
        }
    }
}
