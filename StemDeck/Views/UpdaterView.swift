// Views/UpdaterView.swift
import SwiftUI

struct UpdaterView: View {
    @EnvironmentObject var updater: UpdaterService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundStyle(iconColor.gradient)

            Text(titleText)
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)

            bodySection
            actionSection
        }
        .padding(32)
        .frame(minWidth: 420, maxWidth: 480)
        .background(Color("BackgroundPrimary"))
    }

    // MARK: - Computed helpers (switch on state without Equatable)

    private var iconName: String {
        switch updater.state {
        case .checking:                 return "arrow.triangle.2.circlepath"
        case .upToDate:                 return "checkmark.seal.fill"
        case .updateAvailable:          return "arrow.down.circle.fill"
        case .downloading:              return "arrow.down.to.line.circle.fill"
        case .installing:               return "gear"
        case .readyToRestart:           return "checkmark.circle.fill"
        case .error:                    return "exclamationmark.triangle.fill"
        default:                        return "arrow.triangle.2.circlepath"
        }
    }

    private var iconColor: Color {
        switch updater.state {
        case .upToDate, .readyToRestart: return .green
        case .error:                     return .red
        default:                         return .purple
        }
    }

    private var titleText: String {
        switch updater.state {
        case .checking:                    return "Vérification des mises à jour…"
        case .upToDate:                    return "StemMac est à jour"
        case .updateAvailable(let r):      return "Version \(r.versionString) disponible"
        case .downloading(let p):          return "Téléchargement… \(Int(p * 100))%"
        case .installing:                  return "Installation en cours…"
        case .readyToRestart:              return "Mise à jour installée !"
        case .error(let msg):              return "Erreur : \(msg)"
        default:                           return "Mises à jour"
        }
    }

    @ViewBuilder
    private var bodySection: some View {
        switch updater.state {
        case .upToDate:
            Text("Vous utilisez la version \(updater.currentVersion), la plus récente.")
                .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)

        case .updateAvailable:
            ScrollView {
                Text(updater.releaseNotes)
                    .font(.callout).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)

        case .downloading(let p):
            ProgressView(value: p).progressViewStyle(.linear).tint(.purple)

        case .installing:
            ProgressView().progressViewStyle(.circular)

        case .readyToRestart:
            Text("Redémarrez StemMac pour utiliser la nouvelle version.")
                .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        HStack(spacing: 12) {
            switch updater.state {
            case .updateAvailable(let r):
                Button("Plus tard") { dismiss() }.buttonStyle(.bordered)
                Button("Installer") { updater.downloadAndInstall(r) }
                    .buttonStyle(.borderedProminent).tint(.purple)

            case .readyToRestart:
                Button("Plus tard") { dismiss() }.buttonStyle(.bordered)
                Button("Redémarrer") { updater.relaunch() }
                    .buttonStyle(.borderedProminent).tint(.green)

            case .upToDate, .error:
                Button("Fermer") { dismiss() }
                    .buttonStyle(.borderedProminent).tint(.purple)

            default:
                EmptyView()
            }
        }
    }
}
