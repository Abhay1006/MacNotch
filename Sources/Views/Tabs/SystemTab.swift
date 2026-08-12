import SwiftUI

struct SystemTab: View {
    @ObservedObject var system: SystemManager
    @ObservedObject var audio: AudioManager

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                batteryWidget

                Divider()
                    .background(Color.white.opacity(0.08))
                    .frame(height: 40)

                VStack(spacing: 8) {
                    volumeControl
                    brightnessControl
                }
            }

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 2)

            HStack(spacing: 16) {
                MeterBar(icon: "cpu", label: "CPU", percentage: system.cpuUsage)
                MeterBar(icon: "memorychip", label: "RAM", percentage: system.ramUsage)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 16)
    }

    // MARK: - Battery

    private var batteryWidget: some View {
        VStack(alignment: .center, spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 3.5)
                    .frame(width: 38, height: 38)

                Circle()
                    .trim(from: 0.0, to: CGFloat(system.batteryPercentage) / 100.0)
                    .stroke(batteryColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .frame(width: 38, height: 38)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    if system.isBatteryCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 7))
                            .foregroundColor(.green)
                    }
                    Text("\(system.batteryPercentage)%")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            Text("Battery")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(system.batteryPercentage) percent\(system.isBatteryCharging ? ", charging" : "")")
    }

    private var batteryColor: Color {
        if system.isBatteryCharging { return .green }
        return system.batteryPercentage < 20 ? .red : .pink
    }

    // MARK: - Volume

    private var volumeControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Button(action: { audio.toggleMute() }) {
                    Image(systemName: volumeIcon)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(audio.isMuted ? "Unmute" : "Mute")

                Text("Volume")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("\(audio.displayVolume)%")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }

            Slider(
                value: Binding(
                    get: { Double(audio.volume) },
                    set: { audio.setVolume(Int($0)) }
                ),
                in: 0...100
            )
            .accentColor(.pink)
            .accessibilityLabel("Output volume")
        }
    }

    private var volumeIcon: String {
        let level = audio.displayVolume
        if level == 0 { return "speaker.slash.fill" }
        if level < 33 { return "speaker.wave.1.fill" }
        if level < 66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    // MARK: - Brightness

    private var brightnessControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: brightnessIcon)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.7))

                Text("Brightness")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("\(system.systemBrightness)%")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }

            Slider(
                value: Binding(
                    get: { Double(system.systemBrightness) },
                    set: { system.setBrightness(Int($0)) }
                ),
                in: 0...100
            )
            .accentColor(.pink)
            .accessibilityLabel("Display brightness")
        }
    }

    private var brightnessIcon: String {
        if system.systemBrightness < 33 { return "sun.min.fill" }
        if system.systemBrightness < 66 { return "sun.max" }
        return "sun.max.fill"
    }
}

/// Labelled progress bar used for the CPU and RAM readouts.
struct MeterBar: View {
    let icon: String
    let label: String
    let percentage: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(.pink)
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("\(percentage)%")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.pink)
                        .frame(width: geo.size.width * CGFloat(min(100, max(0, percentage))) / 100.0, height: 4)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) usage \(percentage) percent")
    }
}
