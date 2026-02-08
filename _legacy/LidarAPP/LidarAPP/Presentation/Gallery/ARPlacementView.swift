import SwiftUI

struct ARPlacementView: View {
    let scan: ScanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black

            VStack {
                Text("Nasměrujte kameru na rovný povrch")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 60)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
    }
}
