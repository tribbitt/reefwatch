import SwiftUI
import MapKit

struct MapTabView: View {
    @EnvironmentObject private var viewModel: ReefRankingViewModel

    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 160),
        span:   MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 220)
    )

    @State private var cameraPosition: MapCameraPosition = .region(initialRegion)
    /// Cached visible region from the last camera change. Drives the zoom
    /// stepper math and the label-visibility threshold.
    @State private var visibleRegion: MKCoordinateRegion = initialRegion

    /// Pin labels are the dominant render cost when hundreds of annotations
    /// are on screen — only draw them when the user has zoomed in far enough
    /// that they're actually legible.
    private var showLabels: Bool { visibleRegion.span.latitudeDelta < 25 }

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                ForEach(viewModel.rankedReefs) { reef in
                    Annotation(
                        reef.station.name,
                        coordinate: CLLocationCoordinate2D(
                            latitude:  reef.station.latitude,
                            longitude: reef.station.longitude
                        ),
                        anchor: .center
                    ) {
                        NavigationLink(value: reef) {
                            ReefPinView(reef: reef, showLabel: showLabels)
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Reef Map")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: RankedReef.self) { reef in
                ReefDetailView(reef: reef)
            }
            .overlay(alignment: .topTrailing) {
                ZoomStepper(zoomIn:  { zoom(by: 0.5) },
                            zoomOut: { zoom(by: 2.0) })
                    .padding(.trailing, 12)
                    .padding(.top, 12)
            }
            .overlay(alignment: .bottom) {
                if viewModel.rankedReefs.isEmpty {
                    Text("Loading reef data…")
                        .font(.footnote)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private func zoom(by factor: Double) {
        let span = visibleRegion.span
        let newSpan = MKCoordinateSpan(
            latitudeDelta:  min(max(span.latitudeDelta  * factor, 0.2), 170),
            longitudeDelta: min(max(span.longitudeDelta * factor, 0.2), 350)
        )
        let newRegion = MKCoordinateRegion(center: visibleRegion.center, span: newSpan)
        withAnimation(.easeInOut(duration: 0.25)) {
            cameraPosition = .region(newRegion)
        }
        visibleRegion = newRegion
    }
}

private struct ZoomStepper: View {
    let zoomIn:  () -> Void
    let zoomOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: zoomIn) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            Divider().frame(width: 36)
            Button(action: zoomOut) {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
        }
        .foregroundStyle(.primary)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }
}

private struct ReefPinView: View {
    let reef: RankedReef
    var showLabel: Bool = true

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(pinFill)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .overlay(
                        // Dashed ring on gridded-source pins, matching the list
                        // view's "estimated, not directly measured" indicator.
                        reef.station.source.isGriddedEstimate
                            ? AnyView(Circle().stroke(Color.white, style: StrokeStyle(lineWidth: 1, dash: [2, 2])).padding(2))
                            : AnyView(EmptyView())
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                Text(pinValue)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            if showLabel {
                Text(reef.station.name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.ultraThinMaterial, in: Capsule())
                    .opacity(0.85)
            }
        }
    }

    /// Gray for NaN reefs so they're visually deprioritized; otherwise the
    /// alert-level palette.
    private var pinFill: Color {
        reef.hasNaN ? Color.gray.opacity(0.55) : reef.alertLevel.color
    }

    /// Question mark for NaN, otherwise the rounded integer DHW.
    private var pinValue: String {
        reef.hasNaN ? "?" : String(format: "%.0f", reef.currentDHW)
    }
}
