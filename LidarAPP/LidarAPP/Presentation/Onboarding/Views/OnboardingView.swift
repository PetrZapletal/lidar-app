import SwiftUI

/// Vícekrokový onboarding flow zobrazený při prvním spuštění aplikace
struct OnboardingView: View {
    let services: ServiceContainer
    @State private var viewModel: OnboardingViewModel

    init(services: ServiceContainer) {
        self.services = services
        self._viewModel = State(initialValue: OnboardingViewModel(services: services))
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(.systemBackground), Color.blue.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    if !viewModel.isLastPage {
                        Button("Přeskočit") {
                            viewModel.skipOnboarding()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("onboarding.skipButton")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .frame(height: 44)

                // Page content
                TabView(selection: $viewModel.currentPage) {
                    welcomePage
                        .tag(0)

                    lidarCheckPage
                        .tag(1)

                    permissionsPage
                        .tag(2)

                    tutorialPage
                        .tag(3)

                    readyPage
                        .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentPage)

                // Bottom controls
                VStack(spacing: 16) {
                    // Page indicator
                    HStack(spacing: 8) {
                        ForEach(0..<viewModel.totalPages, id: \.self) { index in
                            Circle()
                                .fill(index == viewModel.currentPage ? Color.blue : Color.secondary.opacity(0.3))
                                .frame(width: index == viewModel.currentPage ? 10 : 8,
                                       height: index == viewModel.currentPage ? 10 : 8)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.currentPage)
                        }
                    }
                    .accessibilityIdentifier("onboarding.pageIndicator")

                    // Action button
                    Button(action: {
                        if viewModel.isLastPage {
                            viewModel.completeOnboarding()
                        } else {
                            viewModel.nextPage()
                        }
                    }) {
                        Text(viewModel.isLastPage ? "Začít skenovat" : "Další")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 40)
                    .accessibilityIdentifier(viewModel.isLastPage ? "onboarding.startButton" : "onboarding.nextButton")
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            services.debugStream.trackViewAppeared("OnboardingView")
        }
        .accessibilityIdentifier("onboarding.view")
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)
                .symbolEffect(.pulse, options: .repeating)

            Text("Vítejte")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("LiDAR Scanner")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)

            Text("Profesionální 3D skenování prostoru pomocí LiDAR senzoru vašeho zařízení.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .accessibilityIdentifier("onboarding.welcomePage")
    }

    // MARK: - Page 2: LiDAR Check

    private var lidarCheckPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: viewModel.hasLiDAR ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(viewModel.hasLiDAR ? .green : .red)
                .symbolEffect(.bounce, value: viewModel.hasLiDAR)

            Text("Kontrola LiDAR")
                .font(.largeTitle)
                .fontWeight(.bold)

            if viewModel.hasLiDAR {
                VStack(spacing: 12) {
                    Text("LiDAR senzor nalezen")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)

                    Text("Vaše zařízení podporuje přesné 3D skenování s LiDAR senzorem.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                VStack(spacing: 12) {
                    Text("LiDAR senzor nenalezen")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)

                    Text("Vaše zařízení nemá LiDAR senzor. Některé funkce budou omezeny. Pro plnou funkčnost je potřeba iPhone 12 Pro nebo novější.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()
            Spacer()
        }
        .accessibilityIdentifier("onboarding.lidarCheckPage")
    }

    // MARK: - Page 3: Permissions

    private var permissionsPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: viewModel.cameraPermissionGranted ? "camera.fill" : "camera")
                .font(.system(size: 80))
                .foregroundStyle(viewModel.cameraPermissionGranted ? .green : .blue)

            Text("Oprávnění")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Pro skenování potřebujeme přístup ke kameře a LiDAR senzoru.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if viewModel.cameraPermissionGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Přístup ke kameře povolen")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Button(action: {
                    Task {
                        await viewModel.requestCameraPermission()
                    }
                }) {
                    HStack(spacing: 8) {
                        if viewModel.isRequestingPermission {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Povolit přístup ke kameře")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.isRequestingPermission)
                .accessibilityIdentifier("onboarding.cameraPermissionButton")
            }

            Spacer()
            Spacer()
        }
        .accessibilityIdentifier("onboarding.permissionsPage")
    }

    // MARK: - Page 4: Tutorial

    private var tutorialPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Jak skenovat")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Tři režimy skenování pro různé situace")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 16) {
                ForEach(ScanMode.allCases, id: \.rawValue) { mode in
                    scanModeCard(mode: mode)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
        .accessibilityIdentifier("onboarding.tutorialPage")
    }

    private func scanModeCard(mode: ScanMode) -> some View {
        HStack(spacing: 16) {
            Image(systemName: mode.icon)
                .font(.title2)
                .foregroundStyle(mode.color)
                .frame(width: 44, height: 44)
                .background(mode.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(mode.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(mode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Page 5: Ready

    private var readyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green.gradient)
                .symbolEffect(.bounce)

            Text("Připraveno")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Vše je nastaveno. Můžete začít skenovat svůj první 3D model.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Summary
            VStack(spacing: 12) {
                summaryRow(
                    icon: viewModel.hasLiDAR ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    text: viewModel.hasLiDAR ? "LiDAR senzor k dispozici" : "LiDAR senzor chybí",
                    color: viewModel.hasLiDAR ? .green : .orange
                )

                summaryRow(
                    icon: viewModel.cameraPermissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    text: viewModel.cameraPermissionGranted ? "Kamera povolena" : "Kamera nepovolena",
                    color: viewModel.cameraPermissionGranted ? .green : .orange
                )
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .accessibilityIdentifier("onboarding.readyPage")
    }

    private func summaryRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
