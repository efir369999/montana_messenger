import Foundation
import CallKit
import AVFoundation

// CallKit has one provider per application. UUIDs route actions; creating a room must
// never replace the provider receiving a pair call's actions.
final class MTSystemCalls: NSObject, CXProviderDelegate, CXCallObserverDelegate {
    static let shared = MTSystemCalls()
    let provider: CXProvider
    let controller = CXCallController()
    private let observer = CXCallObserver()
    private struct Entry {
        weak var delegate: CXProviderDelegate?
        let recents: Bool
    }
    private var calls: [UUID: Entry] = [:]
    /// ONE KEEPER OF THE SYSTEM'S LIST (15.10.2026): the call machine kept a second observer of the same list for its sweep;
    /// the list is read here, and its changes are handed to the machine.
    var systemCalls: [CXCall] { observer.calls }
    var onCallChanged: ((CXCall) -> Void)?

    private override init() {
        let configuration = CXProviderConfiguration()
        configuration.iconTemplateImageData = MontanaCall.appGlyphTemplate()
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 2
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: .main)
        observer.setDelegate(self, queue: .main)
    }

    func register(_ uuid: UUID, delegate: CXProviderDelegate, recents: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        calls[uuid] = Entry(delegate: delegate, recents: recents)
        // Rooms are private and cannot coexist with a pair call. Keep their privacy
        // through asynchronous teardown and any busy push reported during that teardown.
        let configuration = provider.configuration
        configuration.includesCallsInRecents = !calls.values.contains { !$0.recents }
        provider.configuration = configuration
    }
    func forget(_ uuid: UUID) { calls.removeValue(forKey: uuid) }
    /// IS THIS CALL OF THE SYSTEM'S LIST THIS DELEGATE'S (15.10.2026, the critic of No.69): the call machine kept its own copy of
    /// the same set for its sweep and its first report, and the copy outlived the keeper's forget and reset. One keeper answers
    /// both; a room's call is not the pair machine's -- the delegate decides. The waiver's witness (listedOurs) keeps every
    /// call of ours, the room's included.
    func holds(_ uuid: UUID, for delegate: CXProviderDelegate) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return calls[uuid]?.delegate === delegate
    }
    /// THE WAIVER'S WITNESS (15.10.2026, iPhone 17 Pro Max on 2210): PushKit may waive the report of a push, and three waived
    /// pushes that came with no call of ours alive were answered by nothing -- the system killed the app each time (0xBAADCA11).
    /// The waiver stands only on a call the system itself lists as ours and not ended: its own list, never our machine's state.
    func listedOurs() -> MTListedCall? {
        dispatchPrecondition(condition: .onQueue(.main))
        return Self.listed(observer.calls, ours: Set(calls.keys))
    }
    static func listed(_ system: [CXCall], ours: Set<UUID>) -> MTListedCall? {
        system.first { call in !call.hasEnded && ours.contains(call.uuid) }.map { call in MTListedCall(uuid: call.uuid) }
    }

    private var delegates: [CXProviderDelegate] {
        var seen = Set<ObjectIdentifier>()
        return calls.values.compactMap(\.delegate).filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
    private func owner(_ action: CXCallAction) -> CXProviderDelegate? {
        let delegate = calls[action.callUUID]?.delegate
        MontanaTrace.mark("callkit_action", "kind=\(type(of: action)) registered=\(delegate == nil ? 0 : 1)")
        return delegate
    }
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        if call.hasEnded { calls.removeValue(forKey: call.uuid) }
        onCallChanged?(call)
    }
    func providerDidReset(_ provider: CXProvider) {
        let targets = delegates
        calls.removeAll()
        MTCallAudioOwner.shared.deactivate("system", session: AVAudioSession.sharedInstance())
        for target in targets { target.providerDidReset(provider) }
    }
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        guard let target = owner(action) else { action.fail(); return }
        if target.provider?(provider, perform: action) == nil { action.fail() }
    }
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let target = owner(action) else { action.fail(); return }
        if target.provider?(provider, perform: action) == nil { action.fail() }
    }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard let target = owner(action) else { action.fulfill(); return }
        if target.provider?(provider, perform: action) == nil { action.fulfill() }
    }
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let target = owner(action) else { action.fail(); return }
        if target.provider?(provider, perform: action) == nil { action.fail() }
    }
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        guard let target = owner(action) else { action.fail(); return }
        if target.provider?(provider, perform: action) == nil { action.fail() }
    }
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        guard let call = action as? CXCallAction, let target = owner(call) else { return }
        target.provider?(provider, timedOutPerforming: action)
    }
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MTCallAudioOwner.shared.activate("system", session: audioSession) { [weak self] in
            for target in self?.delegates ?? [] { target.provider?(provider, didActivate: audioSession) }
        }
    }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MTCallAudioOwner.shared.deactivate("system", session: audioSession)
        for target in delegates { target.provider?(provider, didDeactivate: audioSession) }
    }
}

/// A call the system lists as ours and alive. Born only here, from the system's own list: a PushKit waiver cannot be built
/// from belief (MTVoipReport.mustReport).
struct MTListedCall {
    let uuid: UUID
    fileprivate init(uuid: UUID) { self.uuid = uuid }
}
