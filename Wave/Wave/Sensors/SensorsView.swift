import SwiftUI

struct SensorsView: View {
    @StateObject private var model = SensorsModel()

    var body: some View {
        List {
            motionSection
            environmentSection
            locationSection
            deviceSection
            Section {
                EmptyView()
            } footer: {
                Text("Toutes les valeurs sont lues en direct. iOS ne donne pas l'accès au capteur de luminosité ambiante. Magnéto et Ultrasons ont leur propre onglet pour aller plus loin.")
            }
        }
        .navigationTitle("Capteurs")
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: Mouvement

    private var motionSection: some View {
        Section("Mouvement") {
            SensorTile(icon: "move.3d", tint: .blue, title: "Accéléromètre",
                       value: String(format: "%.2f g", model.accelMagnitude),
                       detail: axes(model.accel), history: model.accelHistory, color: .blue)
            SensorTile(icon: "gyroscope", tint: .indigo, title: "Gyroscope",
                       value: String(format: "%.2f rad/s", model.rotationMagnitude),
                       detail: axes(model.rotation), history: model.rotationHistory, color: .indigo)
            SensorTile(icon: "location.north.circle", tint: .pink, title: "Magnétomètre",
                       value: model.fieldCalibrated ? String(format: "%.0f µT", model.field) : "calibration…",
                       detail: nil, history: model.fieldHistory, color: .pink)
            LabeledContent("Inclinaison (roll/pitch/yaw)") {
                Text(String(format: "%.0f° / %.0f° / %.0f°",
                            model.attitude.x * 180 / .pi,
                            model.attitude.y * 180 / .pi,
                            model.attitude.z * 180 / .pi))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Environnement

    private var environmentSection: some View {
        Section("Environnement") {
            if let p = model.pressure {
                SensorTile(icon: "barometer", tint: .teal, title: "Pression",
                           value: String(format: "%.2f kPa", p),
                           detail: String(format: "%.1f hPa", p * 10),
                           history: model.pressureHistory, color: .teal)
                LabeledContent("Altitude relative") {
                    Text(String(format: "%+.1f m", model.relativeAltitude))
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            } else {
                Label("Baromètre indisponible sur cet appareil.", systemImage: "barometer")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Localisation

    private var locationSection: some View {
        Section("Localisation") {
            if model.locationDenied {
                Label("Localisation refusée (Réglages › Wave).", systemImage: "location.slash")
                    .foregroundStyle(.orange)
            }
            LabeledContent("Boussole", value: model.heading.map { String(format: "%.0f° %@", $0, compassName($0)) } ?? "—")
            LabeledContent("Vitesse", value: model.speed.map { String(format: "%.1f km/h", $0 * 3.6) } ?? "—")
            LabeledContent("Altitude GPS", value: model.altitude.map { String(format: "%.0f m", $0) } ?? "—")
            LabeledContent("Précision", value: model.horizontalAccuracy.map { String(format: "± %.0f m", $0) } ?? "—")
            LabeledContent("Pas (depuis l'ouverture)", value: model.steps.map(String.init) ?? "—")
            if let c = model.cadence, c > 0 {
                LabeledContent("Cadence", value: String(format: "%.0f pas/min", c))
            }
        }
    }

    // MARK: Appareil

    private var deviceSection: some View {
        Section("Appareil") {
            LabeledContent("Proximité") {
                Label(model.proximityNear ? "Objet proche" : "Dégagé",
                      systemImage: model.proximityNear ? "hand.raised.fill" : "hand.raised.slash")
                    .foregroundStyle(model.proximityNear ? .orange : .secondary)
            }
            LabeledContent("Batterie", value: model.batteryText)
            LabeledContent("Température interne") {
                HStack(spacing: 6) {
                    Circle().fill(Color(model.thermalColor)).frame(width: 9, height: 9)
                    Text(model.thermalText).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func axes(_ v: SIMD3<Double>) -> String {
        String(format: "X %.2f  Y %.2f  Z %.2f", v.x, v.y, v.z)
    }
}

/// Tuile avec valeur, détail des axes et courbe en direct.
private struct SensorTile: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    var detail: String?
    let history: [Double]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                Spacer()
                Text(value)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
            }
            if history.count > 1 {
                Sparkline(values: history, color: color)
                    .frame(height: 34)
            }
            if let detail {
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
