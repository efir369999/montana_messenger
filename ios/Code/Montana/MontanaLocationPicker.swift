//
//  MontanaLocationPicker.swift
//  Montana — a Montana messenger
//

import SwiftUI
import MapKit
import CoreLocation

/// A PLACE IS CHOSEN ON A MAP, NOT TYPED (the author's word 22.09: the button must open what the
/// reference opens, one to one in look and in working). The page carries the map above and two
/// things under it: THIS spot, with the accuracy the phone actually has, and what stands around.
///
/// Everything on it is the platform's own: MKMapView for the map, MKLocalPointsOfInterestRequest
/// for what stands around, CLLocationManager for the spot. The reference asks its own servers for
/// the places; we ask the platform — the same list, and no third party in the road: no key, no
/// account and no address of ours leaves the phone.
struct MTPlace: Identifiable, Equatable {
    let id: String
    let name: String
    let street: String
    let latitude: Double
    let longitude: Double
    let glyph: String
    let tint: Color

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    static func == (a: MTPlace, b: MTPlace) -> Bool { a.id == b.id }

    /// THE COLOUR AND THE GLYPH COME FROM THE KIND OF PLACE, as the reference draws them: a park is
    /// green, a shop is amber, a place to eat is amber, anything else wears the pin. One table, so
    /// no row invents a colour of its own.
    static func dress(_ category: MKPointOfInterestCategory?) -> (String, Color) {
        guard let category else { return ("mappin", Color(white: 0.45)) }
        switch category {
        case .park, .nationalPark, .beach, .campground, .zoo, .aquarium:
            return ("figure.walk", Color(red: 0.30, green: 0.72, blue: 0.36))
        case .foodMarket, .store, .bakery:
            return ("cart.fill", Color(red: 0.95, green: 0.68, blue: 0.16))
        case .restaurant, .cafe, .brewery, .winery, .nightlife:
            return ("fork.knife", Color(red: 0.95, green: 0.55, blue: 0.16))
        case .hotel:
            return ("bed.double.fill", Color(red: 0.36, green: 0.55, blue: 0.95))
        case .hospital, .pharmacy:
            return ("cross.case.fill", Color(red: 0.90, green: 0.35, blue: 0.35))
        case .museum, .theater, .movieTheater, .library:
            return ("building.columns.fill", Color(red: 0.55, green: 0.45, blue: 0.90))
        case .gasStation, .parking, .evCharger:
            return ("car.fill", Color(red: 0.36, green: 0.55, blue: 0.95))
        case .fitnessCenter, .stadium:
            return ("figure.run", Color(red: 0.30, green: 0.72, blue: 0.36))
        case .school, .university:
            return ("graduationcap.fill", Color(red: 0.55, green: 0.45, blue: 0.90))
        case .bank, .atm:
            return ("banknote.fill", Color(red: 0.30, green: 0.72, blue: 0.36))
        default:
            return ("bag.fill", Color(red: 0.95, green: 0.68, blue: 0.16))
        }
    }
}

/// WHETHER THIS PHONE MAY SAY WHERE IT IS — ONE OWNER FOR THE WHOLE CLIENT ([C-1], the author's
/// word 23.09: «the location must be determined, and if there is no access — asked for; and put
/// the access in the privacy menu with a road to the settings, as the local network and the
/// notifications have»). The page and the privacy row read the SAME state and press the SAME
/// thing: a permission nobody has asked for is asked here; one already decided is changed where
/// the system keeps it, because iOS has no call that would change it for us.
///
/// Before this, the page kept a manager of its own and told nobody what it found: a phone whose
/// owner had refused once, long ago, stood on «Locating…» for ever — there was no word, no way
/// back and nothing to read (the author's screenshot 23.09, 00:19).
@MainActor
final class MTLocationAccess: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = MTLocationAccess()

    private let manager = CLLocationManager()
    private var watchers = 0

    @Published private(set) var status: CLAuthorizationStatus = .notDetermined
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var accuracy: CLLocationAccuracy = 0

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        status = manager.authorizationStatus
    }

    var allowed: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var refused: Bool { status == .denied || status == .restricted }

    /// The word a person reads, and the key the catalog holds — the shape the notifications row wears.
    var word: String {
        if allowed { return "Allowed" }
        if refused { return "Denied" }
        return "Not asked"
    }

    /// THE ONE TAP, WRITTEN ONCE: never asked — ask; already decided — open where the system keeps
    /// it. The page's row and the privacy row press this, so the two can never disagree.
    func tap() {
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { MontanaSystemSettings.open() }
    }

    /// While a page watches, the phone says where it is; when the last watcher leaves, it stops.
    func watch() {
        watchers += 1
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if allowed { manager.startUpdatingLocation() }
        MontanaTrace.mark("place_access", "watch=\(watchers) access=\(word)")
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
        if watchers == 0 { manager.stopUpdatingLocation() }
    }

    /// Read anew when the person comes back from the system settings — that return IS the event;
    /// a timer would count blind between events.
    func refresh() {
        status = manager.authorizationStatus
        if allowed, watchers > 0 { manager.startUpdatingLocation() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            self.status = m.authorizationStatus
            MontanaTrace.mark("place_access", "access=\(self.word)")
            if self.allowed, self.watchers > 0 { m.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let last = locs.last else { return }
        Task { @MainActor in
            self.coordinate = last.coordinate
            self.accuracy = max(0, last.horizontalAccuracy)
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        MontanaTrace.markFolded("place_access", "the phone could not say where it is", window: 60, key: "fail")
    }

    /// THE FIX AS A VALUE THAT CAN BE COMPARED: a coordinate is a pair of numbers with no equality
    /// of its own, and a page must be able to notice that it changed.
    var fixKey: String {
        guard let c = coordinate else { return "" }
        return "\(c.latitude),\(c.longitude)"
    }

    /// A length as a person reads it, by the platform's own measure of length.
    static func lengthWords(_ metres: CLLocationAccuracy) -> String {
        let f = MeasurementFormatter()
        f.locale = MTLanguage.locale
        f.unitOptions = .naturalScale
        f.numberFormatter.maximumFractionDigits = 0
        return f.string(from: Measurement(value: max(1, metres.rounded()), unit: UnitLength.meters))
    }
}

/// WHAT STANDS AROUND THIS SPOT. The permission and the spot belong to MTLocationAccess; this holds
/// only the places, asked of the platform once, at the first fix.
@MainActor
final class MTPlaceFinder: ObservableObject {
    @Published var places: [MTPlace] = []
    private var asked = false

    /// A refusal speaks: an empty list with no word is the thing nobody can read afterwards.
    func lookAround(_ c: CLLocationCoordinate2D) {
        guard !asked else { return }
        asked = true
        let t0 = Date()
        let request = MKLocalPointsOfInterestRequest(center: c, radius: 1000)
        MKLocalSearch(request: request).start { [weak self] response, error in
            Task { @MainActor in
                guard let self else { return }
                guard let items = response?.mapItems else {
                    MontanaTrace.mark("place_pick", "nothing around: \(error == nil ? "no answer" : "refused")")
                    return
                }
                let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
                var near: [(Double, MTPlace)] = []
                for item in items {
                    guard let name = item.name, let spot = item.placemark.location else { continue }
                    let dress = MTPlace.dress(item.pointOfInterestCategory)
                    let place = MTPlace(id: "\(spot.coordinate.latitude),\(spot.coordinate.longitude),\(name)",
                                        name: name,
                                        street: MTPlaceFinder.street(item.placemark),
                                        latitude: spot.coordinate.latitude,
                                        longitude: spot.coordinate.longitude,
                                        glyph: dress.0, tint: dress.1)
                    near.append((spot.distance(from: here), place))
                }
                near.sort { a, b in a.0 < b.0 }
                self.places = near.map { $0.1 }
                MontanaTrace.mark("place_pick", "around=\(self.places.count) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
            }
        }
    }

    /// The line under a name: the street and the number when the platform knows them, the town when
    /// it does not — the shape the reference's second line wears.
    static func street(_ p: MKPlacemark) -> String {
        var parts: [String] = []
        if let line = p.thoroughfare {
            parts.append(p.subThoroughfare.map { "\(line), \($0)" } ?? line)
        }
        if parts.isEmpty, let town = p.locality { parts.append(town) }
        if parts.isEmpty, let area = p.administrativeArea { parts.append(area) }
        return parts.joined(separator: ", ")
    }
}

/// THE MAP IS THE PLATFORM'S OWN (MKMapView through its own wrapper, the UIKit rule of 18.09): the
/// ring of accuracy is an MKCircle, the spot is one annotation wearing the one pin (MTPinMark) —
/// this person's own face on the page that sends, the plain pin on the page that shows a place.
struct MTLocationMap: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D?
    let accuracy: CLLocationAccuracy
    var face = true            // one's own spot wears one's face; a place that came in wears the pin
    var controls = false       // the viewer's page: the system's own locate button and the map kind
    var span: CLLocationDistance = 700
    var controlsLift: CGFloat = 200

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        if controls {
            map.showsUserLocation = true
            addControls(to: map)
        }
        return map
    }

    /// The locate button is the platform's own (MKUserTrackingButton); the map kind is one system
    /// button beside it, both on one material plate — the right edge the reference keeps.
    private func addControls(to map: MKMapView) {
        let kind = UIButton(type: .system)
        kind.setImage(UIImage(systemName: "map"), for: .normal)
        kind.tintColor = .label
        kind.accessibilityLabel = String(localized: "Map", bundle: MTLanguage.bundle)
        kind.addAction(UIAction { [weak map] _ in
            guard let map else { return }
            map.mapType = map.mapType == .standard ? .hybrid : .standard
        }, for: .touchUpInside)
        let track = MKUserTrackingButton(mapView: map)
        track.tintColor = .label
        let stack = UIStackView(arrangedSubviews: [kind, track])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        let plate = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        plate.layer.cornerRadius = 22
        plate.layer.cornerCurve = .continuous
        plate.clipsToBounds = true
        plate.translatesAutoresizingMaskIntoConstraints = false
        plate.contentView.addSubview(stack)
        map.addSubview(plate)
        NSLayoutConstraint.activate([
            kind.widthAnchor.constraint(equalToConstant: 44), kind.heightAnchor.constraint(equalToConstant: 44),
            track.widthAnchor.constraint(equalToConstant: 44), track.heightAnchor.constraint(equalToConstant: 44),
            stack.topAnchor.constraint(equalTo: plate.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: plate.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: plate.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: plate.contentView.trailingAnchor),
            plate.trailingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            plate.bottomAnchor.constraint(equalTo: map.safeAreaLayoutGuide.bottomAnchor, constant: -controlsLift),
        ])
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        guard let c = coordinate else { return }
        context.coordinator.place(c, accuracy: accuracy, on: map)
    }

    func makeCoordinator() -> Coordinator { Coordinator(face: face, span: span) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let reuse = "mt-pin"
        private let face: Bool
        private let span: CLLocationDistance
        private var pin: MKPointAnnotation?
        private var ring: MKCircle?
        private var centred = false
        init(face: Bool, span: CLLocationDistance) { self.face = face; self.span = span }

        func place(_ c: CLLocationCoordinate2D, accuracy: CLLocationAccuracy, on map: MKMapView) {
            if let pin { pin.coordinate = c } else {
                let a = MKPointAnnotation(); a.coordinate = c
                map.addAnnotation(a); pin = a
            }
            if let ring { map.removeOverlay(ring); self.ring = nil }
            if accuracy > 0 {
                let r = MKCircle(center: c, radius: max(30, accuracy))
                map.addOverlay(r); ring = r
            }
            if !centred {
                centred = true
                map.setRegion(MKCoordinateRegion(center: c, latitudinalMeters: span, longitudinalMeters: span), animated: false)
            }
        }

        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let r = MKCircleRenderer(overlay: overlay)
            r.fillColor = UIColor.systemBlue.withAlphaComponent(0.12)
            r.strokeColor = UIColor.white.withAlphaComponent(0.75)
            r.lineWidth = 2
            return r
        }

        /// The one pin, its DOT on the very coordinate: the view is lifted so the dot, not the
        /// middle of the picture, stands where the phone is (the author's word 23.09).
        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }   // one's own blue dot is the platform's
            let v = map.dequeueReusableAnnotationView(withIdentifier: Self.reuse)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: Self.reuse)
            v.annotation = annotation
            v.image = MTPinMark.image(face: face ? MontanaSelfFace.image : nil)
            v.centerOffset = CGPoint(x: 0, y: -MTPinMark.lift)
            return v
        }
    }
}

/// THE ONE PIN OF THE CLIENT: a head, its point, and the DOT under it that marks the exact spot —
/// the head stands ABOVE the place, never on it (the author's word 23.09). The head wears this
/// person's face where it is one's own spot, the platform's pin glyph where it is a place. Drawn
/// once, here, as one picture: the map on the page, the letter's picture and the viewer's map all
/// wear this very picture.
enum MTPinMark {
    static let head: CGFloat = 46
    static let pad: CGFloat = 4                        // room for the shadow, the same on every side
    static let height: CGFloat = 46 + 9 + 3 + 9
    /// How far the picture's middle stands above the dot's middle (the padding is symmetric).
    static let lift: CGFloat = height - 4.5 - height / 2
    private static var plain: UIImage?

    static func image(face: UIImage?) -> UIImage {
        if face == nil, let plain { return plain }
        let size = CGSize(width: head + pad * 2, height: height + pad * 2)
        let blue = UIColor.systemBlue
        let ground = face == nil ? blue : UIColor.white
        let out = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.25).cgColor)
            let headRect = CGRect(x: pad, y: pad, width: head, height: head)
            ground.setFill()
            UIBezierPath(ovalIn: headRect).fill()
            let point = UIBezierPath()
            point.move(to: CGPoint(x: headRect.midX - 7, y: headRect.maxY - 1))
            point.addLine(to: CGPoint(x: headRect.midX + 7, y: headRect.maxY - 1))
            point.addLine(to: CGPoint(x: headRect.midX, y: headRect.maxY + 9))
            point.close()
            point.fill()
            let dot = CGRect(x: headRect.midX - 4.5, y: headRect.maxY + 12, width: 9, height: 9)
            blue.setFill()
            UIBezierPath(ovalIn: dot).fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor.white.setStroke()
            let rim = UIBezierPath(ovalIn: dot.insetBy(dx: 0.75, dy: 0.75)); rim.lineWidth = 1.5; rim.stroke()
            if let face {
                let inner = headRect.insetBy(dx: 3, dy: 3)
                cg.saveGState()
                UIBezierPath(ovalIn: inner).addClip()
                let k = max(inner.width / max(face.size.width, 1), inner.height / max(face.size.height, 1))
                let w = face.size.width * k, h = face.size.height * k
                face.draw(in: CGRect(x: inner.midX - w / 2, y: inner.midY - h / 2, width: w, height: h))
                cg.restoreGState()
            } else if let glyph = UIImage(systemName: "mappin",
                                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold))?
                        .withTintColor(.white, renderingMode: .alwaysOriginal) {
                glyph.draw(at: CGPoint(x: headRect.midX - glyph.size.width / 2, y: headRect.midY - glyph.size.height / 2))
            }
        }
        if face == nil { plain = out }
        return out
    }
}

/// The wire is the same words every living build already reads as text; a build that knows the
/// shape draws the map instead, a build that does not shows the words — nothing new is said on
/// the wire.
struct MTPlaceLetter: Identifiable, Equatable {
    let latitude: Double
    let longitude: Double
    let name: String?
    let street: String?

    var id: String { "\(latitude),\(longitude),\(name ?? "")" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var title: String { name ?? String(localized: "Location", bundle: MTLanguage.bundle) }

    static let pin = "\u{1F4CD}"
    static let road = "https://maps.apple.com/?ll="

    static func link(_ c: CLLocationCoordinate2D, _ shown: String) -> String {
        let query = shown.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Location"
        return road + "\(c.latitude),\(c.longitude)&q=\(query)"
    }
    var mapsURL: URL? { URL(string: Self.link(coordinate, title)) }

    /// The words a place leaves as: the pin and the name, the street when there is one, the link.
    static func words(_ c: CLLocationCoordinate2D, name: String?, street: String?) -> String {
        let shown = name ?? String(localized: "My location", bundle: MTLanguage.bundle)
        var words = pin + " " + shown
        if let street, !street.isEmpty { words += "\n" + street }
        return words + "\n" + link(c, shown)
    }

    /// The same words read back. Only the exact shape is a place: a letter that merely carries a
    /// map link stays a letter of words.
    static func parse(_ text: String) -> MTPlaceLetter? {
        guard text.hasPrefix(pin), text.count < 600 else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard (2...3).contains(lines.count), let last = lines.last, last.hasPrefix(road) else { return nil }
        let pair = last.dropFirst(road.count).prefix { $0 != "&" }
        let parts = pair.split(separator: ",")
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        let shown = String(lines[0].dropFirst(pin.count)).trimmingCharacters(in: .whitespaces)
        let own: Set<String> = ["My location", String(localized: "My location", bundle: MTLanguage.bundle)]
        let street = lines.count == 3 ? lines[1].trimmingCharacters(in: .whitespaces) : ""
        return MTPlaceLetter(latitude: lat, longitude: lon,
                             name: (shown.isEmpty || own.contains(shown)) ? nil : shown,
                             street: street.isEmpty ? nil : street)
    }
}

/// The map picture a letter wears: taken once by the platform's own snapshotter and kept in memory
/// by the place and the size, so a feed that scrolls asks nothing twice.
enum MTPlaceSnapshot {
    private static let cache: NSCache<NSString, UIImage> = MontanaCaches.kept("place-snapshots")
    private static func key(_ c: CLLocationCoordinate2D, _ size: CGSize, _ dark: Bool) -> NSString {
        "\(c.latitude),\(c.longitude),\(Int(size.width))x\(Int(size.height)),\(dark)" as NSString
    }
    static func cached(_ c: CLLocationCoordinate2D, size: CGSize, dark: Bool) -> UIImage? {
        cache.object(forKey: key(c, size, dark))
    }
    static func take(_ c: CLLocationCoordinate2D, size: CGSize, dark: Bool) async -> UIImage? {
        if let hit = cached(c, size: size, dark: dark) { return hit }
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: c, latitudinalMeters: 500, longitudinalMeters: 500)
        o.size = size
        o.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        guard let shot = try? await MKMapSnapshotter(options: o).start() else {
            MontanaTrace.markFolded("place_letter", "the map picture was not taken", window: 60, key: "shot")
            return nil
        }
        cache.setObject(shot.image, forKey: key(c, size, dark))
        return shot.image
    }
}

/// The picture of a place inside a letter: the map, and the one pin with its dot on the spot.
struct MTPlaceMapPlate: View {
    let place: MTPlaceLetter
    let size: CGSize
    @Environment(\.colorScheme) private var scheme
    @State private var shot: UIImage?

    var body: some View {
        ZStack {
            if let shot = shot ?? MTPlaceSnapshot.cached(place.coordinate, size: size, dark: scheme == .dark) {
                Image(uiImage: shot).resizable()
            } else {
                Color(white: 0.2)
            }
            Image(uiImage: MTPinMark.image(face: nil)).offset(y: -MTPinMark.lift)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: place.id) {
            shot = await MTPlaceSnapshot.take(place.coordinate, size: size, dark: scheme == .dark)
        }
    }
}

/// A PLACE OPENED FROM A LETTER (the author's word 23.09, the reference's own page): the map over
/// the whole screen with the pin on the spot, the cross and the share in the bar, the platform's
/// locate button and the map kind at the right edge, and a card below — the name, the street and
/// how far it is from here, and the way there by car and on foot, each opened in the platform's Maps.
struct MTPlaceView: View {
    let place: MTPlaceLetter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.montanaClose) private var montanaClose
    private func leave() { mtLeavePage(montanaClose, dismiss) }
    @ObservedObject private var access = MTLocationAccess.shared
    @State private var drive: TimeInterval?
    @State private var walk: TimeInterval?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MTLocationMap(coordinate: place.coordinate, accuracy: 0, face: false, controls: true, span: 600)
                    .ignoresSafeArea()
                card
            }
            .navigationTitle(Text("Location"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaCloseMark { leave() } }
                ToolbarItem(placement: .topBarTrailing) {
                    MontanaBarMark(glyph: "square.and.arrow.up", label: "Share") {
                        if let u = place.mapsURL { MTShare.present([u]) }
                    }
                }
            }
        }
        .task {
            access.watch()
            MontanaTrace.mark("place_letter", "opened named=\(place.name == nil ? 0 : 1)")
            drive = await Self.eta(to: place, by: .automobile)
            walk = await Self.eta(to: place, by: .walking)
        }
        .onDisappear { access.unwatch() }
    }

    private var card: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "mappin")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Color(UIColor.systemBlue), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.title).font(.headline).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                route("car.fill", drive, MKLaunchOptionsDirectionsModeDriving)
                route("figure.walk", walk, MKLaunchOptionsDirectionsModeWalking)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// The street, and how far the place is from where this phone stands — when it may say.
    private var subtitle: String {
        var parts: [String] = []
        if let s = place.street { parts.append(s) }
        if let me = access.coordinate {
            let d = CLLocation(latitude: me.latitude, longitude: me.longitude)
                .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
            parts.append(String(format: String(localized: "%@ from you", bundle: MTLanguage.bundle), MTLocationAccess.lengthWords(d)))
        }
        return parts.joined(separator: " \u{2022} ")
    }

    private func route(_ glyph: String, _ time: TimeInterval?, _ mode: String) -> some View {
        Button {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
            item.name = place.title
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
        } label: {
            HStack(spacing: 8) {
                Image(systemName: glyph)
                if let time { Text(Self.minutes(time)) }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color(UIColor.systemBlue), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    static func minutes(_ t: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        var cal = Calendar.current; cal.locale = MTLanguage.locale; f.calendar = cal
        f.unitsStyle = .abbreviated
        f.allowedUnits = t < 3600 ? [.minute] : [.hour, .minute]
        return f.string(from: max(60, t)) ?? ""
    }

    /// The way there as the platform counts it; no answer is no time, never a guess.
    static func eta(to place: MTPlaceLetter, by kind: MKDirectionsTransportType) async -> TimeInterval? {
        let r = MKDirections.Request()
        r.source = MKMapItem.forCurrentLocation()
        r.destination = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        r.transportType = kind
        return try? await MKDirections(request: r).calculateETA().expectedTravelTime
    }
}

/// WHO ASKED FOR A PLACE, AND WHERE THE LETTER GOES. The page stands over EVERYTHING — the tabs
/// and the open chat alike — so no bar of another screen can be drawn over its own; the ask
/// carries the correspondence the letter belongs to.
struct MTPlaceAsk: Identifiable {
    let chat: String
    let conv: String
    var id: String { chat + " " + conv }
}

/// Every living build reads it as words, exactly as it read yesterday's — the page above only chooses
/// WHICH spot, it does not invent a new word for the wire. A place carries its name and its street where
/// «My location» used to stand alone. One owner: the page is raised from the chat and answered here, so
/// the words a place wears are written in one place. The store's send belongs to the main actor, and so
/// does this: only screens call it (the build of 1885 stopped on it -- a free function is not the main
/// actor's until it says so).
@MainActor
func mtSendPlace(_ store: ChatStore, _ c: CLLocationCoordinate2D, name: String?, street: String?, ask: MTPlaceAsk) {
    _ = store.send(text: MTPlaceLetter.words(c, name: name, street: street), chat: ask.chat, convRef: ask.conv)
}

/// The page itself: the map, THIS spot, and what stands around — in that order, as the reference
/// stands them. Its bar is its own: the cross on the left, the search on the right, and nothing
/// else — the page no longer rides under the chat's bar, where the chat's back chevron and the
/// chat's name were drawn over it (the author's word 23.09).
struct MTLocationPicker: View {
    var onPick: (CLLocationCoordinate2D, String?, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.montanaClose) private var montanaClose
    private func leave() { mtLeavePage(montanaClose, dismiss) }
    @StateObject private var finder = MTPlaceFinder()
    @ObservedObject private var access = MTLocationAccess.shared
    @State private var query = ""
    @State private var searching = false

    private var shown: [MTPlace] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return finder.places }
        return finder.places.filter { $0.name.lowercased().contains(q) || $0.street.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MTLocationMap(coordinate: access.coordinate, accuracy: access.accuracy)
                    .frame(height: 300)
                List {
                    Section {
                        Button { pressSend() } label: { sendRow }
                            .buttonStyle(.plain)
                            .disabled(!access.refused && access.coordinate == nil)
                    }
                    if !shown.isEmpty {
                        Section {
                            ForEach(shown) { place in
                                Button { send(place.coordinate, place.name, place.street) } label: { row(place) }
                                    .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Or choose a place")
                        }
                    }
                }
                .listStyle(.plain)
                // ONLY THE MAGNIFIER STANDS UNTIL IT IS PRESSED (the author's word 23.09): the platform
                // lays a searchable page's field along the bottom for good; the field is given to the
                // page only while the magnifier has asked for it, and leaves with its own cancel.
                .modifier(MTSearchWhenAsked(asked: $searching, text: $query))
            }
            .navigationTitle(Text("Location"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaCloseMark { leave() } }
                ToolbarItem(placement: .topBarTrailing) {
                    MontanaBarMark(glyph: "magnifyingglass", label: "Search") { searching = true }
                }
            }
        }
        .task {
            access.watch()
            if let c = access.coordinate { finder.lookAround(c) }   // a fix this page did not wait for
        }
        .onDisappear { access.unwatch() }
        // The first fix asks what stands around; the return from the system settings is read anew.
        .onChange(of: access.fixKey) { _, _ in if let c = access.coordinate { finder.lookAround(c) } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            access.refresh()
        }
    }

    /// THIS SPOT: the platform's pin in its circle, the words, and the accuracy the phone has right
    /// now. The WHOLE row answers the finger, not its text alone (the author's rule 22.09). Where
    /// the phone is not allowed to say, the same row says so and leads to where that is changed.
    private var sendRow: some View {
        HStack(spacing: 14) {
            Image(systemName: access.refused ? "location.slash.fill" : "mappin")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(access.refused ? Color(white: 0.45) : Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                if access.refused {
                    Text("Turn on location").font(.body)
                } else {
                    Text("Send This Location").font(.body)
                }
                Text(state).font(.footnote).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            if access.refused {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color(white: 0.45))
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// The second line of that row, in three states and no more: refused, still looking, known.
    private var state: String {
        if access.refused { return String(localized: "Montana has no access to your location", bundle: MTLanguage.bundle) }
        guard access.coordinate != nil else { return String(localized: "Locating…", bundle: MTLanguage.bundle) }
        return String(format: String(localized: "Accurate to %@", bundle: MTLanguage.bundle), MTLocationAccess.lengthWords(access.accuracy))
    }

    private func pressSend() {
        if access.refused { access.tap() } else { send(access.coordinate, nil, nil) }
    }

    private func row(_ place: MTPlace) -> some View {
        HStack(spacing: 14) {
            Image(systemName: place.glyph)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(place.tint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body).lineLimit(1)
                if !place.street.isEmpty {
                    Text(place.street).font(.footnote).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func send(_ c: CLLocationCoordinate2D?, _ name: String?, _ street: String?) {
        guard let c else { return }
        MontanaTrace.mark("place_pick", name == nil ? "this spot" : "a place around")
        onPick(c, name, street)
        leave()
    }
}

/// The platform's search field, present only while it is asked for; its own cancel takes it away
/// together with the words typed into it.
struct MTSearchWhenAsked: ViewModifier {
    @Binding var asked: Bool
    @Binding var text: String
    func body(content: Content) -> some View {
        if asked {
            content
                .searchable(text: $text, isPresented: $asked, prompt: Text("Search"))
                .onDisappear { text = "" }
        } else {
            content
        }
    }
}
