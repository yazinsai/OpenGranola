import AppKit
import SwiftUI

/// Root container for the setup wizard. Manages step transitions and detection.
struct SetupWizardView: View {
    @Binding var isPresented: Bool
    let settings: SettingsStore
    let isReconfiguration: Bool

    @State private var viewModel = WizardViewModel()

    init(
        isPresented: Binding<Bool>,
        settings: SettingsStore,
        isReconfiguration: Bool = false
    ) {
        self._isPresented = isPresented
        self.settings = settings
        self.isReconfiguration = isReconfiguration
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(visibleSteps, id: \.rawValue) { step in
                    Circle()
                        .fill(
                            step == viewModel.currentStep
                                ? Color.accentTeal
                                : step.rawValue < viewModel.currentStep.rawValue
                                ? Color.accentTeal.opacity(0.4)
                                : Color.secondary.opacity(0.3)
                        )
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 16)

            Group {
                switch viewModel.currentStep {
                case .intent:
                    IntentStepView(viewModel: viewModel)

                case .languagePrivacy:
                    LanguagePrivacyStepView(viewModel: viewModel)

                case .providerSetup:
                    ProviderSetupStepView(viewModel: viewModel)

                case .confirmation:
                    ConfirmationStepView(
                        viewModel: viewModel,
                        settings: settings,
                        onComplete: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                        },
                        onCustomize: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                            }
                        }
                    )
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.currentStep)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("wizard.root")
        .task {
            await runDetection()
        }
    }

    private var visibleSteps: [WizardStep] {
        var steps: [WizardStep] = [.intent]

        if let intent = viewModel.intent {
            let nextStep = RecommendationEngine.nextStepAfterIntent(intent: intent, snapshot: viewModel.snapshot)
            if nextStep == .languagePrivacy {
                steps.append(.languagePrivacy)
            }
            if intent != .transcribe {
                steps.append(.providerSetup)
            }
        } else {
            steps.append(.languagePrivacy)
            steps.append(.providerSetup)
        }

        steps.append(.confirmation)
        return steps
    }

    private func runDetection() async {
        let detector = SetupDetector(
            dependencies: SetupDetector.LiveDependencies(settings: settings)
        )
        let snapshot = await detector.detect()
        viewModel.configure(
            with: snapshot,
            currentSettings: settings,
            isReconfiguration: isReconfiguration
        )
    }
}
