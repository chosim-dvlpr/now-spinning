import CoreAudio
import AudioToolbox
import AppKit
import Combine

// ponytail: 시간축 RMS 밴드. 주파수 스펙트럼 원하면 vDSP FFT로 교체
// CoreAudio 프로세스 탭(macOS 14.2+): 화면 기록 권한 없이 "시스템 오디오 녹음" 권한만 사용
final class AudioTap: ObservableObject {
    static let bandCount = 24
    @Published var bands = [Float](repeating: 0, count: bandCount)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var peak: Float = 0.01

    private var granted = false
    private var currentPid: pid_t = 0
    private var wantedPid: pid_t = 0

    func start() {
        requestPermission { granted in
            NSLog("AudioCapture permission granted=\(granted)")
            self.granted = granted
            granted ? self.retarget(pid: self.wantedPid) : self.startFake()
        }
    }

    /// 재생 중인 앱의 pid가 바뀌면 탭을 옮긴다.
    func retarget(pid: pid_t) {
        wantedPid = pid
        guard granted, pid != currentPid else { return }
        detach()
        currentPid = pid
        if pid > 0 { _ = attach(pid: pid) }
    }

    private func detach() {
        if let procID, aggID != kAudioObjectUnknown {
            AudioDeviceStop(aggID, procID)
            AudioDeviceDestroyIOProcID(aggID, procID)
        }
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil; aggID = kAudioObjectUnknown; tapID = kAudioObjectUnknown
        DispatchQueue.main.async { self.bands = [Float](repeating: 0, count: Self.bandCount) }
    }

    // 프로세스 탭은 권한 없으면 오류 없이 무음을 주므로 TCC에 직접 요청 (AudioCap 방식)
    private func requestPermission(_ done: @escaping (Bool) -> Void) {
        typealias Fn = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
        guard let h = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_NOW),
              let sym = dlsym(h, "TCCAccessRequest") else { done(false); return }
        unsafeBitCast(sym, to: Fn.self)("kTCCServiceAudioCapture" as CFString, nil) { ok in DispatchQueue.main.async { done(ok) } }
    }

    // 권한 거부 시: 소리와 무관한 사인파 혼합 애니메이션 (ponytail: 비트 동기화 없음)
    private func startFake() {
        var t: Float = 0
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            t += 0.12
            self.bands = (0..<Self.bandCount).map { i in
                let x = Float(i) * 0.45
                let v = sin(t * 1.3 + x) * 0.35 + sin(t * 2.1 - x * 1.7) * 0.25 + sin(t * 0.7 + x * 0.3) * 0.2
                return max(0.05, 0.45 + v * 0.5)
            }
        }
    }

    private func attach(pid: pid_t) -> Bool {
        var pidVar = pid
        var obj = AudioObjectID(kAudioObjectUnknown)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<pid_t>.size), &pidVar, &size, &obj) == noErr,
              obj != kAudioObjectUnknown else { return false }

        let desc = CATapDescription(stereoMixdownOfProcesses: [obj])
        desc.isPrivate = true
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { NSLog("tap create failed (권한 거부?)"); return false }

        // 집계 장치에 기본 출력 장치를 넣어야 클록이 돌아 IOProc가 호출됨
        var outDev = AudioObjectID(kAudioObjectUnknown)
        var outAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var outSize = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &outAddr, 0, nil, &outSize, &outDev)
        var uidAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        AudioObjectGetPropertyData(outDev, &uidAddr, 0, nil, &uidSize, &uid)

        let agg: [String: Any] = [
            kAudioAggregateDeviceMainSubDeviceKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
            kAudioAggregateDeviceNameKey: "NowSpinningTap",
            kAudioAggregateDeviceUIDKey: "io.github.chosim-dvlpr.NowSpinning.tap",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        guard AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID) == noErr else { NSLog("agg failed"); return false }

        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { [weak self] _, inData, _, _, _ in
            self?.process(inData)
        }
        guard status == noErr, AudioDeviceStart(aggID, procID) == noErr else { NSLog("start failed"); return false }
        NSLog("AudioTap attached to pid \(pid)")
        return true
    }

    private func process(_ list: UnsafePointer<AudioBufferList>) {
        let buf = list.pointee.mBuffers
        guard let data = buf.mData else { return }
        let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
        guard n > 0 else { return }
        let s = data.assumingMemoryBound(to: Float.self)
        let chunk = max(1, n / Self.bandCount)
        var out = [Float](repeating: 0, count: Self.bandCount)
        for b in 0..<Self.bandCount {
            let lo = b * chunk, hi = min(n, lo + chunk)
            var sum: Float = 0
            for i in lo..<hi { sum += s[i] * s[i] }
            out[b] = (sum / Float(max(1, hi - lo))).squareRoot()
        }
        // 자동 게인: 최근 피크 기준으로 정규화해 볼륨과 무관하게 파형이 차도록
        peak = max(peak * 0.995, out.max() ?? 0, 0.005)
        out = out.map { min(1, $0 / peak) }
        DispatchQueue.main.async { self.bands = out }
    }
}
