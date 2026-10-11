// Models/AppState.swift
import SwiftUI
import Combine

enum AppScreen {
    case setup
    case importing
    case processing
    case studio
    case library
}

@MainActor
final class AppState: ObservableObject {

    // Navigation
    @Published var screen:          AppScreen = .importing
    @Published var showImportSheet  = false
    @Published var showLibrary      = false
    @Published var showSettings     = false

    // Active job
    @Published var currentJob:      StemJob?      = nil
    @Published var jobProgress:     JobProgress   = .init()

    // Stem selection
    @Published var selectedStems:   Set<StemKind> = Set(StemKind.processable)

    // Playback
    @Published var isPlaying        = false
    @Published var loopEnabled      = false
    @Published var loopStart:       Double = 0
    @Published var loopEnd:         Double = 0
    @Published var playheadPosition: Double = 0
    @Published var zoomLevel:       Double = 1.0

    // Library
    @Published var libraryJobs:     [StemJob] = []

    // Setup
    @Published var isSetupComplete: Bool = false

    // Backend — starts false, becomes true once /docs responds
    @Published var backendReady:    Bool = false
    @Published var backendPort:     Int  = 8000

    init() {
        let installed = PythonRuntimeService.shared.isInstalled
        isSetupComplete = installed
        screen = installed ? .importing : .setup
    }

    func toggleStem(_ kind: StemKind) {
        let all = Set(StemKind.processable)
        if selectedStems == all {
            selectedStems = [kind]
        } else if selectedStems.contains(kind) {
            selectedStems.remove(kind)
            if selectedStems.isEmpty { selectedStems = all }
        } else {
            selectedStems.insert(kind)
        }
    }

    func resetForNewJob() {
        currentJob      = nil
        jobProgress     = .init()
        isPlaying       = false
        loopEnabled     = false
        playheadPosition = 0
        zoomLevel       = 1.0
        screen          = .importing
    }
}

struct JobProgress {
    var phase:        String = ""
    var percent:      Double = 0
    var message:      String = ""
    var isComplete    = false
    var isFailed      = false
    var errorMessage: String? = nil
}

struct SetupProgress {
    var currentStep: String = "Préparation…"
    var percent:     Double = 0
}
