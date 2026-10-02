import SwiftUI

enum Route: Hashable {
    case device(UUID)
    case gatt(UUID)
    case finder(UUID)
}

extension View {
    /// Destinations de navigation communes à tous les onglets.
    func bloutoussDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .device(let id):
                DeviceDetailView(deviceID: id)
            case .gatt(let id):
                GATTExplorerView(deviceID: id)
            case .finder(let id):
                FinderView(deviceID: id)
            }
        }
    }
}

extension BluetoothDevice {
    var signalColor: Color {
        if smoothedRSSI >= -60 { return .green }
        if smoothedRSSI >= -75 { return .yellow }
        if smoothedRSSI >= -90 { return .orange }
        return .red
    }
}

struct DeviceIcon: View {
    let kind: DeviceKind
    var color: Color = .accentColor
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    let monospaced: Bool

    init(_ title: String, _ value: String, monospaced: Bool = false) {
        self.title = title
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        Group {
            if monospaced {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(value)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else {
                HStack {
                    Text(title)
                    Spacer()
                    Text(value)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = value
            } label: {
                Label("Copier", systemImage: "doc.on.doc")
            }
        }
    }
}

struct FavoriteBanner: View {
    let alert: FavoriteAlert

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.title)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Favori à proximité")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(alert.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 8)
        .padding(.horizontal)
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
