import Foundation
import Dispatch
import HAP

#if os(macOS)
import Darwin
#else
import Glibc
#endif

struct BridgeConfig: Codable {
    let fanHost: String
    let fanPort: Int
    let bridgeName: String
    let fanName: String
    let lightName: String
    let temperatureName: String
    let humidityName: String
    let setupCode: String
}

struct FanCommand: Codable {
    let power: String?
    let speedPercent: Int?
    let lightPercent: Int?
    let autoMode: Bool?
    let whoosh: Bool?
    let eco: Bool?
}

struct FanStatus {
    var fanOn = false
    var autoMode = false
    var whoosh = false
    var eco = false
    var speedPercent = 0
    var downlightOn = false
    var downlightPercent = 0
    var tempC: Double?
    var humidityPercent: Double?
    var make: String?
    var model: String?
    var softwareVersion: String?
    var firmwareVersion: String?
}

final class HaikuTCPAPI {
    private let config: BridgeConfig
    private let prefix: [UInt8] = [18, 7, 18, 5, 26, 3]

    init(config: BridgeConfig) {
        self.config = config
    }

    private func frame(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0xC0]
        for b in bytes {
            if b == 0xC0 {
                out.append(contentsOf: [0xDB, 0xDC])
            } else if b == 0xDB {
                out.append(contentsOf: [0xDB, 0xDD])
            } else {
                out.append(b)
            }
        }
        out.append(0xC0)
        return out
    }

    private func unframe(_ buffer: [UInt8]) -> [[UInt8]] {
        var packets: [[UInt8]] = []
        var current: [UInt8] = []
        var inFrame = false

        for b in buffer {
            if b == 0xC0 {
                if inFrame && !current.isEmpty {
                    packets.append(unstuff(current))
                }
                current.removeAll(keepingCapacity: true)
                inFrame = true
            } else if inFrame {
                current.append(b)
            }
        }

        return packets
    }

    private func unstuff(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0xDB, i + 1 < bytes.count {
                if bytes[i + 1] == 0xDC {
                    out.append(0xC0)
                    i += 2
                    continue
                } else if bytes[i + 1] == 0xDD {
                    out.append(0xDB)
                    i += 2
                    continue
                }
            }
            out.append(bytes[i])
            i += 1
        }
        return out
    }

    private func withSocket<T>(_ body: (_ fd: Int32) throws -> T) throws -> T {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { throw NSError(domain: "socket", code: 1) }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
        withUnsafePointer(to: &timeout) {
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        withUnsafePointer(to: &timeout) {
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(config.fanPort).bigEndian

        let pton = config.fanHost.withCString { cs in
            inet_pton(AF_INET, cs, &addr.sin_addr)
        }
        if pton != 1 { throw NSError(domain: "socket", code: 2) }

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult != 0 { throw NSError(domain: "socket", code: 3) }
        return try body(fd)
    }

    private func writeAll(fd: Int32, bytes: [UInt8]) throws {
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBytes {
                Darwin.write(fd, $0.baseAddress!.advanced(by: sent), bytes.count - sent)
            }
            if n <= 0 { throw NSError(domain: "socket", code: 4) }
            sent += n
        }
    }

    private func requestFrames() -> [[UInt8]] {
        [
            prefix + [18, 4, 26, 2, 8, 3],
            prefix + [18, 4, 26, 2, 8, 6],
            prefix + [18, 2, 26, 0],
        ]
    }

    private func parseVarint(_ data: [UInt8], _ index: inout Int) -> UInt64? {
        var shift: UInt64 = 0
        var value: UInt64 = 0

        while index < data.count {
            let byte = data[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 { return value }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    private func decodeString(_ bytes: [UInt8]) -> String? {
        guard let text = String(bytes: bytes, encoding: .utf8) else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return cleaned.isEmpty ? nil : cleaned
    }

    private func parseDeviceInfo(_ bytes: [UInt8], status: inout FanStatus) {
        var i = 0
        while i < bytes.count {
            guard let tag = parseVarint(bytes, &i) else { return }
            let field = Int(tag >> 3)
            let wire = Int(tag & 0x07)
            if wire != 2 {
                switch wire {
                case 0: _ = parseVarint(bytes, &i)
                case 1: i += 8
                case 5: i += 4
                default: return
                }
                continue
            }

            guard let lenV = parseVarint(bytes, &i) else { return }
            let len = Int(lenV)
            if len < 0 || i + len > bytes.count { return }
            let sub = Array(bytes[i..<(i + len)])
            i += len

            if let text = decodeString(sub) {
                if field == 2 { status.softwareVersion = text }
                if field == 3 { status.firmwareVersion = text }
            }
        }
    }

    private func parsePacket(_ packet: [UInt8], status: inout FanStatus) {
        var idx = 0
        var lightTarget = "downlight"

        func walk(_ bytes: [UInt8], _ i: inout Int) {
            while i < bytes.count {
                guard let tag = parseVarint(bytes, &i) else { return }
                let field = Int(tag >> 3)
                let wire = Int(tag & 0x07)

                switch wire {
                case 0:
                    guard let raw = parseVarint(bytes, &i) else { return }
                    let v = Int(raw)
                    switch field {
                    case 43:
                        status.fanOn = v >= 1
                        status.autoMode = v == 2
                    case 46:
                        status.speedPercent = max(0, min(100, v))
                    case 58:
                        status.whoosh = v == 1
                    case 65:
                        status.eco = v == 1
                    case 68:
                        if lightTarget == "downlight" { status.downlightOn = v >= 1 }
                    case 69:
                        if lightTarget == "downlight" { status.downlightPercent = max(0, min(100, v)) }
                    case 82:
                        lightTarget = (v == 2) ? "uplight" : "downlight"
                    case 86:
                        status.tempC = Double(v) / 100.0
                    case 87:
                        status.humidityPercent = Double(v) / 100.0
                    default:
                        break
                    }
                case 1:
                    i += 8
                case 2:
                    guard let lenV = parseVarint(bytes, &i) else { return }
                    let len = Int(lenV)
                    if len < 0 || i + len > bytes.count { return }
                    let sub = Array(bytes[i..<(i + len)])

                    if field == 16 {
                        parseDeviceInfo(sub, status: &status)
                    } else if (field == 56 || field == 59 || field == 76), let text = decodeString(sub) {
                        if status.model == nil { status.model = text }
                    }

                    var subIdx = 0
                    walk(sub, &subIdx)
                    i += len
                case 5:
                    i += 4
                default:
                    return
                }
            }
        }

        walk(packet, &idx)
    }

    func status() async throws -> [String: Any] {
        let packets = try withSocket { fd -> [[UInt8]] in
            for cmd in requestFrames() {
                try writeAll(fd: fd, bytes: frame(cmd))
            }

            var all: [UInt8] = []
            let deadline = Date().addingTimeInterval(1.2)
            var buf = [UInt8](repeating: 0, count: 4096)

            while Date() < deadline {
                let n = read(fd, &buf, buf.count)
                if n > 0 {
                    all.append(contentsOf: buf[0..<n])
                } else {
                    usleep(40_000)
                }
            }

            return unframe(all)
        }

        var status = FanStatus()
        for p in packets {
            parsePacket(p, status: &status)
        }

        if status.make == nil { status.make = "Big Ass Fans / Delta T" }

        return [
            "on": status.fanOn,
            "auto": status.autoMode,
            "whoosh": status.whoosh,
            "eco": status.eco,
            "speedPercent": status.speedPercent,
            "lightPercent": status.downlightOn ? status.downlightPercent : 0,
            "tempC": status.tempC as Any,
            "humidity": status.humidityPercent as Any,
            "make": status.make as Any,
            "model": status.model as Any,
            "softwareVersion": status.softwareVersion as Any,
            "firmwareVersion": status.firmwareVersion as Any,
        ]
    }

    func command(_ cmd: FanCommand) async {
        do {
            try withSocket { fd in
                if let power = cmd.power {
                    let state = power.lowercased() == "on" ? 1 : 0
                    try writeAll(fd: fd, bytes: frame(prefix + [216, 2, UInt8(state)]))
                }

                if let auto = cmd.autoMode {
                    let mode: UInt8 = auto ? 2 : 1
                    try writeAll(fd: fd, bytes: frame(prefix + [216, 2, mode]))
                }

                if let speed = cmd.speedPercent {
                    let s = max(0, min(100, speed))
                    let fanSpeed = UInt8((Double(s) / 100.0 * 7.0).rounded())
                    try writeAll(fd: fd, bytes: frame(prefix + [240, 2, fanSpeed]))
                    if fanSpeed > 0 {
                        try writeAll(fd: fd, bytes: frame(prefix + [216, 2, 1]))
                    }
                }

                if let whoosh = cmd.whoosh {
                    try writeAll(fd: fd, bytes: frame(prefix + [208, 3, whoosh ? 1 : 0]))
                }

                if let eco = cmd.eco {
                    try writeAll(fd: fd, bytes: frame(prefix + [136, 4, eco ? 1 : 0]))
                }

                if let light = cmd.lightPercent {
                    let l = UInt8(max(0, min(100, light)))
                    let isOn: UInt8 = l > 0 ? 1 : 0
                    try writeAll(fd: fd, bytes: frame(prefix + [144, 5, 1]))   // downlight target
                    try writeAll(fd: fd, bytes: frame(prefix + [160, 4, isOn]))
                    if isOn == 1 {
                        try writeAll(fd: fd, bytes: frame(prefix + [168, 4, l]))
                    }
                }

                for query in requestFrames() {
                    try writeAll(fd: fd, bytes: frame(query))
                }
            }
        } catch {
            fputs("Command error: \(error)\n", stderr)
        }
    }
}

final class BridgeDelegate: DeviceDelegate {
    private let api: HaikuTCPAPI
    private let fanService: Service.FanV2
    private let lightService: Service.Lightbulb
    private let tempService: Service.TemperatureSensor
    private let humidityService: Service.HumiditySensor
    private let autoService: Service.Switch
    private let whooshService: Service.Switch
    private let ecoService: Service.Switch
    private let debugTelemetry: Bool

    init(api: HaikuTCPAPI, fanService: Service.FanV2, lightService: Service.Lightbulb, tempService: Service.TemperatureSensor, humidityService: Service.HumiditySensor, autoService: Service.Switch, whooshService: Service.Switch, ecoService: Service.Switch, debugTelemetry: Bool) {
        self.api = api
        self.fanService = fanService
        self.lightService = lightService
        self.tempService = tempService
        self.humidityService = humidityService
        self.autoService = autoService
        self.whooshService = whooshService
        self.ecoService = ecoService
        self.debugTelemetry = debugTelemetry
    }

    func characteristic<T>(_ characteristic: GenericCharacteristic<T>, ofService service: Service, ofAccessory accessory: Accessory, didChangeValue newValue: T?) {
        if service.type == .fanV2 {
            if characteristic.type == .active {
                let isOn = (newValue as? Enums.Active) == .active
                Task { await api.command(FanCommand(power: isOn ? "on" : "off", speedPercent: nil, lightPercent: nil, autoMode: nil, whoosh: nil, eco: nil)) }
            } else if characteristic.type == .rotationSpeed {
                if let speed = newValue as? Float {
                    Task { await api.command(FanCommand(power: nil, speedPercent: max(0, min(100, Int(speed))), lightPercent: nil, autoMode: nil, whoosh: nil, eco: nil)) }
                }
            }
        }

        if service.type == .lightbulb {
            if characteristic.type == .powerState {
                if let on = newValue as? Bool {
                    Task { await api.command(FanCommand(power: nil, speedPercent: nil, lightPercent: on ? 100 : 0, autoMode: nil, whoosh: nil, eco: nil)) }
                }
            } else if characteristic.type == .brightness {
                if let b = newValue as? Int {
                    Task { await api.command(FanCommand(power: nil, speedPercent: nil, lightPercent: max(0, min(100, b)), autoMode: nil, whoosh: nil, eco: nil)) }
                }
            }
        }

        if service.type == .switch, characteristic.type == .powerState, let on = newValue as? Bool {
            if service === autoService {
                Task { await api.command(FanCommand(power: nil, speedPercent: nil, lightPercent: nil, autoMode: on, whoosh: nil, eco: nil)) }
            } else if service === whooshService {
                Task { await api.command(FanCommand(power: nil, speedPercent: nil, lightPercent: nil, autoMode: nil, whoosh: on, eco: nil)) }
            } else if service === ecoService {
                Task { await api.command(FanCommand(power: nil, speedPercent: nil, lightPercent: nil, autoMode: nil, whoosh: nil, eco: on)) }
            }
        }
    }

    private func asDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    func refreshFromFan() async {
        do {
            let s = try await api.status()

            let isOn = (s["on"] as? Bool) == true
            fanService.active.value = isOn ? .active : .inactive
            lightService.powerState.value = ((s["lightPercent"] as? Int) ?? 0) > 0
            autoService.powerState.value = (s["auto"] as? Bool) == true
            whooshService.powerState.value = (s["whoosh"] as? Bool) == true
            ecoService.powerState.value = (s["eco"] as? Bool) == true

            if let speed = s["speedPercent"] as? Int, let rotation = fanService.rotationSpeed {
                rotation.value = Float(max(0, min(100, speed)))
            }
            if let b = s["lightPercent"] as? Int, let brightness = lightService.brightness {
                brightness.value = max(0, min(100, b))
            }
            if let tC = asDouble(s["tempC"]) {
                tempService.currentTemperature.value = Float(tC)
            }
            if let h = asDouble(s["humidity"]) {
                humidityService.currentRelativeHumidity.value = Float(max(0, min(100, h)))
            }

            if debugTelemetry {
                let speed = (s["speedPercent"] as? Int) ?? 0
                let light = (s["lightPercent"] as? Int) ?? 0
                let auto = (s["auto"] as? Bool) == true
                let whoosh = (s["whoosh"] as? Bool) == true
                let eco = (s["eco"] as? Bool) == true
                let temp = asDouble(s["tempC"])
                let humidity = asDouble(s["humidity"])
                let tempText = temp.map { String(format: "%.2f°C", $0) } ?? "n/a"
                let humidityText = humidity.map { String(format: "%.1f%%", $0) } ?? "n/a"
                let make = (s["make"] as? String) ?? "n/a"
                let model = (s["model"] as? String) ?? "n/a"
                let sw = (s["softwareVersion"] as? String) ?? "n/a"
                let fw = (s["firmwareVersion"] as? String) ?? "n/a"
                print("[telemetry] fanOn=\(isOn) auto=\(auto) whoosh=\(whoosh) eco=\(eco) speed=\(speed)% light=\(light)% temp=\(tempText) humidity=\(humidityText) make=\(make) model=\(model) sw=\(sw) fw=\(fw)")
            }
        } catch {
            fputs("Status refresh error: \(error)\n", stderr)
        }
    }
}

func loadConfig(path: String) throws -> BridgeConfig {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(BridgeConfig.self, from: data)
}

let args = Array(CommandLine.arguments.dropFirst())
let debugTelemetry = args.contains("--debug-telemetry")
let printDeviceInfo = args.contains("--print-device-info")
let configPath = args.first(where: { !$0.hasPrefix("--") }) ?? "Config/bridge-config.json"
let config = try loadConfig(path: configPath)
let api = HaikuTCPAPI(config: config)

if printDeviceInfo {
    Task {
        do {
            let status = try await api.status()
            print("make=\((status["make"] as? String) ?? "n/a")")
            print("model=\((status["model"] as? String) ?? "n/a")")
            print("softwareVersion=\((status["softwareVersion"] as? String) ?? "n/a")")
            print("firmwareVersion=\((status["firmwareVersion"] as? String) ?? "n/a")")
            print("temperatureC=\((status["tempC"] as? Double).map { String(format: "%.2f", $0) } ?? "n/a")")
            print("humidity=\((status["humidity"] as? Double).map { String(format: "%.1f", $0) } ?? "n/a")")
            exit(0)
        } catch {
            fputs("Device info error: \(error)\n", stderr)
            exit(1)
        }
    }
    dispatchMain()
}

let fanService = Service.FanV2(characteristics: [.name(config.fanName), .rotationSpeed()])
let fanAccessory = Accessory(
    info: Service.Info(name: config.fanName, serialNumber: "HAIKU-FAN-001"),
    type: .fan,
    services: [fanService]
)

let lightService = Service.Lightbulb(characteristics: [.name(config.lightName), .brightness()])
let lightAccessory = Accessory(
    info: Service.Info(name: config.lightName, serialNumber: "HAIKU-LIGHT-001"),
    type: .lightbulb,
    services: [lightService]
)

let tempService = Service.TemperatureSensor(characteristics: [.name(config.temperatureName)])
let tempAccessory = Accessory(
    info: Service.Info(name: config.temperatureName, serialNumber: "HAIKU-TEMP-001"),
    type: .sensor,
    services: [tempService]
)

let humidityService = Service.HumiditySensor(characteristics: [.name(config.humidityName)])
let humidityAccessory = Accessory(
    info: Service.Info(name: config.humidityName, serialNumber: "HAIKU-HUM-001"),
    type: .sensor,
    services: [humidityService]
)

let autoService = Service.Switch(characteristics: [.name("\(config.fanName) Auto")])
let autoAccessory = Accessory(
    info: Service.Info(name: "\(config.fanName) Auto", serialNumber: "HAIKU-AUTO-001"),
    type: .switch,
    services: [autoService]
)

let whooshService = Service.Switch(characteristics: [.name("\(config.fanName) Whoosh")])
let whooshAccessory = Accessory(
    info: Service.Info(name: "\(config.fanName) Whoosh", serialNumber: "HAIKU-WHOOSH-001"),
    type: .switch,
    services: [whooshService]
)

let ecoService = Service.Switch(characteristics: [.name("\(config.fanName) Eco")])
let ecoAccessory = Accessory(
    info: Service.Info(name: "\(config.fanName) Eco", serialNumber: "HAIKU-ECO-001"),
    type: .switch,
    services: [ecoService]
)

let storage = FileStorage(filename: "hap-configuration.json")
let device = Device(
    bridgeInfo: Service.Info(name: config.bridgeName, serialNumber: "HAIKU-BRIDGE-001"),
    setupCode: .override(config.setupCode),
    storage: storage,
    accessories: [fanAccessory, lightAccessory, tempAccessory, humidityAccessory, autoAccessory, whooshAccessory, ecoAccessory]
)

let delegate = BridgeDelegate(api: api, fanService: fanService, lightService: lightService, tempService: tempService, humidityService: humidityService, autoService: autoService, whooshService: whooshService, ecoService: ecoService, debugTelemetry: debugTelemetry)
device.delegate = delegate
let server = try Server(device: device)

print("Bridge: \(config.bridgeName)")
print("Setup code: \(config.setupCode)")
print("Pairing QR:")
print(device.setupQRCode.asText)
if debugTelemetry {
    print("Telemetry debug: ON")
}

let timer = DispatchSource.makeTimerSource()
timer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(8))
timer.setEventHandler { Task { await delegate.refreshFromFan() } }
timer.resume()

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)

let stopSemaphore = DispatchSemaphore(value: 0)
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)

sigintSource.setEventHandler { stopSemaphore.signal() }
sigtermSource.setEventHandler { stopSemaphore.signal() }

sigintSource.resume()
sigtermSource.resume()

_ = stopSemaphore.wait(timeout: .distantFuture)

try server.stop()
