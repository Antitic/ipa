import Foundation
import CoreBluetooth
import Combine

final class BLEScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published private(set) var devices: [BLEDevice] = []
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    /// Appareil dont le nom est en cours de lecture (connexion brève).
    @Published private(set) var resolvingID: UUID?

    /// Connexion brève aux appareils sans nom pour lire leur nom (caractéristique 2A00).
    var resolveNames: Bool {
        get { UserDefaults.standard.object(forKey: "bleResolveNames") as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "bleResolveNames")
            if newValue { pumpResolver() }
        }
    }

    private var central: CBCentralManager?
    private var store: [UUID: BLEDevice] = [:]
    private var wantsScan = false
    private var publishTimer: Timer?
    /// Nombre d'écrans qui utilisent le scan (liste + fiche). Le scan ne s'arrête que
    /// quand plus aucun écran n'en a besoin : auparavant, ouvrir la fiche d'un appareil
    /// déclenchait `onDisappear` de la liste et coupait le scan (chaud/froid figé).
    private var users = 0
    private var paused = false

    private var peripherals: [UUID: CBPeripheral] = [:]
    private var sessions: [UUID: GATTSession] = [:]
    private var resolveQueue: [UUID] = []
    private var resolveTried: Set<UUID> = []
    private var resolverSession: GATTSession?
    private var knownNames: [String: String] = UserDefaults.standard.dictionary(forKey: "bleKnownNames") as? [String: String] ?? [:]

    func acquire() {
        users += 1
        if !paused { start() }
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 { stop() }
    }

    /// Pause / reprise demandée par l'utilisateur.
    func togglePause() {
        if isScanning {
            paused = true
            stop()
        } else {
            paused = false
            start()
        }
    }

    func start() {
        wantsScan = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScan()
        }
        if publishTimer == nil {
            let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
                self?.publish()
            }
            // Mode « common » : la liste continue de se mettre à jour pendant le défilement.
            RunLoop.main.add(timer, forMode: .common)
            publishTimer = timer
        }
    }

    func stop() {
        wantsScan = false
        central?.stopScan()
        isScanning = false
        publishTimer?.invalidate()
        publishTimer = nil
        cancelResolver()
        publish()
    }

    func clear() {
        store.removeAll()
        devices = []
        resolveQueue.removeAll()
        resolveTried.removeAll()
    }

    func device(_ id: UUID) -> BLEDevice? { store[id] }

    private func beginScan() {
        central?.scanForPeripherals(withServices: nil,
                                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
    }

    private func publish() {
        // On oublie les appareils silencieux depuis 2 minutes (sauf ceux qu'on explore).
        let cutoff = Date().addingTimeInterval(-120)
        store = store.filter { $0.value.lastSeen > cutoff || sessions[$0.key] != nil }
        peripherals = peripherals.filter { store[$0.key] != nil || sessions[$0.key] != nil }
        devices = store.values.sorted { $0.rssi > $1.rssi }
    }

    // MARK: - Connexion GATT

    func session(for id: UUID) -> GATTSession? {
        if let s = sessions[id] { return s }
        guard let p = peripherals[id] ?? central?.retrievePeripherals(withIdentifiers: [id]).first else { return nil }
        peripherals[id] = p
        let s = GATTSession(peripheral: p)
        s.onName = { [weak self] name in self?.setName(name, for: id) }
        sessions[id] = s
        return s
    }

    func connect(_ id: UUID) {
        guard central?.state == .poweredOn, let s = session(for: id) else { return }
        if resolverSession?.peripheral.identifier == id { cancelResolver() }
        s.willConnect()
        central?.connect(s.peripheral)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak s] in
            guard let self, let s, s.state == .connecting else { return }
            self.central?.cancelPeripheralConnection(s.peripheral)
            s.didFail("délai dépassé")
        }
    }

    func disconnect(_ id: UUID) {
        guard let s = sessions[id] else { return }
        central?.cancelPeripheralConnection(s.peripheral)
        s.didDisconnect(nil)
        sessions[id] = nil
    }

    // MARK: - Lecture des noms

    private func setName(_ name: String, for id: UUID) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        knownNames[id.uuidString] = clean
        if knownNames.count > 500 { knownNames.removeValue(forKey: knownNames.keys.first!) }
        UserDefaults.standard.set(knownNames, forKey: "bleKnownNames")
        if var d = store[id], d.name == nil || d.nameIsResolved {
            d.name = clean
            d.nameIsResolved = true
            d.info = BLEDecoder.decode(d)
            store[id] = d
        }
    }

    private func enqueueForName(_ d: BLEDevice) {
        guard resolveNames, d.name == nil, d.connectable, d.rssi > -85,
              !resolveTried.contains(d.id), !resolveQueue.contains(d.id) else { return }
        resolveQueue.append(d.id)
        pumpResolver()
    }

    private func pumpResolver() {
        guard resolverSession == nil, resolveNames, isScanning, central?.state == .poweredOn else { return }
        while let id = resolveQueue.first {
            resolveQueue.removeFirst()
            resolveTried.insert(id)
            guard sessions[id] == nil, let p = peripherals[id], store[id]?.name == nil else { continue }
            let s = GATTSession(peripheral: p)
            s.onName = { [weak self] name in
                self?.setName(name, for: id)
                self?.finishResolver(id)
            }
            resolverSession = s
            resolvingID = id
            s.willConnect()
            central?.connect(p)
            // Abandon au bout de 6 s : on passe à l'appareil suivant.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                self?.finishResolver(id)
            }
            return
        }
    }

    private func finishResolver(_ id: UUID) {
        guard let s = resolverSession, s.peripheral.identifier == id else { return }
        central?.cancelPeripheralConnection(s.peripheral)
        s.didDisconnect(nil)
        resolverSession = nil
        resolvingID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.pumpResolver() }
    }

    private func cancelResolver() {
        if let s = resolverSession {
            central?.cancelPeripheralConnection(s.peripheral)
            s.didDisconnect(nil)
        }
        resolverSession = nil
        resolvingID = nil
    }

    private func sessionFor(_ peripheral: CBPeripheral) -> GATTSession? {
        if let s = sessions[peripheral.identifier] { return s }
        if let s = resolverSession, s.peripheral.identifier == peripheral.identifier { return s }
        return nil
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if central.state == .poweredOn && wantsScan {
            beginScan()
        } else if central.state != .poweredOn {
            isScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let r = RSSI.intValue
        guard r < 0, r > -120 else { return }
        let now = Date()
        peripherals[peripheral.identifier] = peripheral
        var d = store[peripheral.identifier] ?? BLEDevice(id: peripheral.identifier, firstSeen: now, lastSeen: now)

        if let n = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !n.isEmpty {
            d.name = n
            d.nameIsResolved = false
        } else if d.name == nil, let n = peripheral.name, !n.isEmpty {
            d.name = n
        } else if d.name == nil, let n = knownNames[peripheral.identifier.uuidString] {
            d.name = n
            d.nameIsResolved = true
        }
        d.rssi = d.history.isEmpty ? r : Int((Double(d.rssi) * 0.6 + Double(r) * 0.4).rounded())
        d.history.append(r)
        if d.history.count > 90 { d.history.removeFirst(d.history.count - 90) }
        d.lastSeen = now

        if let m = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data { d.manufacturerData = m }
        if let s = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] { d.serviceUUIDs.formUnion(s) }
        if let s = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] { d.serviceUUIDs.formUnion(s) }
        if let sd = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (k, v) in sd { d.serviceData[k] = v }
        }
        if let tx = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber { d.txPower = tx.intValue }
        if let c = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber { d.connectable = c.boolValue }

        d.info = BLEDecoder.decode(d)
        store[peripheral.identifier] = d
        enqueueForName(d)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        sessionFor(peripheral)?.didConnect()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        sessionFor(peripheral)?.didFail(error?.localizedDescription ?? "connexion impossible")
        if resolverSession?.peripheral.identifier == peripheral.identifier { finishResolver(peripheral.identifier) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        sessionFor(peripheral)?.didDisconnect(error)
    }
}
