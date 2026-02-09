import SwiftUI
import simd

/// Interactive measurement overlay for the AR scanning view.
/// Provides a floating toolbar for mode selection, point visualization,
/// result display, and a measurement history list.
struct InteractiveMeasurementView: View {
    let services: ServiceContainer
    @State private var viewModel: MeasurementViewModel

    init(services: ServiceContainer) {
        self.services = services
        self._viewModel = State(initialValue: MeasurementViewModel(services: services))
    }

    var body: some View {
        ZStack {
            // Instruction text at top
            VStack {
                instructionBanner
                    .padding(.top, 8)
                Spacer()
            }

            // Point markers overlay
            pointMarkersOverlay

            // Result display
            if !viewModel.currentResult.isEmpty {
                VStack {
                    Spacer()
                    resultBanner
                        .padding(.bottom, 160)
                }
            }

            // Bottom toolbar
            VStack {
                Spacer()

                // Action buttons (undo, clear, complete)
                actionBar
                    .padding(.bottom, 8)

                // Mode selector toolbar
                modeSelector
                    .padding(.bottom, 16)
            }

            // Measurement list panel (slide from right)
            if viewModel.showMeasurementList {
                measurementListPanel
            }
        }
    }

    // MARK: - Instruction Banner

    private var instructionBanner: some View {
        Text(viewModel.instructionText)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(MeasurementViewModel.MeasurementMode.allCases, id: \.self) { mode in
                modeButton(mode)
            }

            Divider()
                .frame(height: 30)
                .padding(.horizontal, 4)

            // Unit picker
            unitPicker

            Divider()
                .frame(height: 30)
                .padding(.horizontal, 4)

            // Measurement list toggle
            listToggleButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func modeButton(_ mode: MeasurementViewModel.MeasurementMode) -> some View {
        Button {
            viewModel.switchMode(mode)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16, weight: .medium))
                Text(mode.label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(viewModel.activeMode == mode ? .white : .secondary)
            .frame(width: 56, height: 44)
            .background(
                viewModel.activeMode == mode
                    ? AnyShapeStyle(.blue.opacity(0.6))
                    : AnyShapeStyle(.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("measurement_mode_\(mode.rawValue)")
    }

    // MARK: - Unit Picker

    private var unitPicker: some View {
        Menu {
            ForEach(MeasurementUnit.allCases, id: \.self) { unit in
                Button {
                    viewModel.changeUnit(unit)
                } label: {
                    HStack {
                        Text(unit.symbol)
                        if viewModel.selectedUnit == unit {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(viewModel.selectedUnit.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 44)
        }
        .accessibilityIdentifier("measurement_unit_picker")
    }

    // MARK: - List Toggle

    private var listToggleButton: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                viewModel.showMeasurementList.toggle()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(viewModel.showMeasurementList ? .blue : .white)
                    .frame(width: 36, height: 44)

                if !viewModel.measurements.isEmpty {
                    Text("\(viewModel.measurements.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.red, in: Capsule())
                        .offset(x: 4, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("measurement_list_toggle")
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 16) {
            // Undo button
            if viewModel.canUndo {
                actionButton(icon: "arrow.uturn.backward", label: "Zpet") {
                    viewModel.undoLastPoint()
                }
                .accessibilityIdentifier("measurement_undo")
            }

            // Complete button (for area mode)
            if viewModel.activeMode == .area && viewModel.canCompleteMeasurement {
                Button {
                    viewModel.completeMeasurement()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                        Text("Dokoncit")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.green.opacity(0.8), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("measurement_complete")
            }

            // Clear button
            if viewModel.canUndo {
                actionButton(icon: "xmark.circle", label: "Vymazat") {
                    viewModel.clearPoints()
                }
                .accessibilityIdentifier("measurement_clear")
            }
        }
    }

    private func actionButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Result Banner

    private var resultBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.activeMode.icon)
                .font(.system(size: 18))
                .foregroundStyle(.blue)

            Text(viewModel.currentResult)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityIdentifier("measurement_result")
    }

    // MARK: - Point Markers Overlay

    private var pointMarkersOverlay: some View {
        // Visual indicators for placed measurement points
        // In a full AR integration, these would be projected to screen coordinates
        // via the AR camera's projection matrix.
        // Here we show a count indicator for placed points.
        VStack {
            HStack {
                Spacer()
                if !viewModel.placedPoints.isEmpty {
                    pointCountBadge
                        .padding(.trailing, 16)
                }
            }
            .padding(.top, 60)
            Spacer()
        }
    }

    private var pointCountBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 14))
            Text("\(viewModel.placedPoints.count) / \(viewModel.activeMode.minimumPoints)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.blue.opacity(0.7), in: Capsule())
        .accessibilityIdentifier("measurement_point_count")
    }

    // MARK: - Measurement List Panel

    private var measurementListPanel: some View {
        HStack {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Mereni")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    if !viewModel.measurements.isEmpty {
                        Button {
                            viewModel.clearAllMeasurements()
                        } label: {
                            Text("Vymazat vse")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("measurement_clear_all")
                    }

                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            viewModel.showMeasurementList = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                if viewModel.measurements.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "ruler")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Zadna mereni")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.measurements) { measurement in
                                measurementRow(measurement)
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
            .frame(width: 280)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.3), radius: 10, x: -2, y: 2)
            .padding(.trailing, 16)
            .padding(.vertical, 80)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .accessibilityIdentifier("measurement_list_panel")
    }

    private func measurementRow(_ measurement: Measurement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: measurement.type.icon)
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(measurement.formattedValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                if let label = measurement.label {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(measurement.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                viewModel.deleteMeasurement(measurement)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        InteractiveMeasurementView(services: ServiceContainer())
    }
}
