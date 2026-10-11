// Views/LibraryView.swift
// Library panel: lists past jobs, allows reopening or deleting.

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""

    private var filtered: [StemJob] {
        if searchText.isEmpty { return appState.libraryJobs }
        return appState.libraryJobs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button {
                    appState.screen = .importing
                    appState.showLibrary = false
                } label: {
                    Label("Retour", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Text("Bibliothèque")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color("BackgroundSecondary"))

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Rechercher…", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Job list
            if filtered.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Aucun projet sauvegardé")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(filtered) { job in
                        LibraryRow(job: job) {
                            appState.currentJob = job
                            appState.screen = .studio
                        }
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { filtered[$0].id }
                        appState.libraryJobs.removeAll { ids.contains($0.id) }
                        Task {
                            for id in ids {
                                // Corbeille du backend : récupérable depuis l'interface web StemDeck
                                try? await BackendService.shared.trashJob(id: id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color.clear)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color("BackgroundPrimary"))
        .task { await reload() }
    }

    /// La bibliothèque vient du backend (persistante dans ~/Documents/StemDeck/jobs).
    private func reload() async {
        guard let jobs = try? await BackendService.shared.listJobs() else { return }
        appState.libraryJobs = jobs
    }
}

struct LibraryRow: View {
    let job: StemJob
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(.purple.gradient)
                    .frame(width: 36, height: 36)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title)
                        .font(.callout.weight(.medium))
                        .foregroundColor(.white)
                    Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.white.opacity(0.03))
    }
}
