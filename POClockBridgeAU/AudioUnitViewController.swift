import AudioToolbox
import CoreAudioKit
import UIKit

final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private var audioUnit: POClockAudioUnit?
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let meter = UIProgressView(progressViewStyle: .default)
    private let thresholdSlider = UISlider()
    private let smoothingSlider = UISlider()
    private let phaseSlider = UISlider()
    private let autoThresholdSwitch = UISwitch()
    private let transportSwitch = UISwitch()
    private let channelControl = UISegmentedControl(items: ["L", "R"])
    private let ppqnControl = UISegmentedControl(items: ["Auto", "1", "2", "4", "12", "24", "48"])
    private let outputControl = UISegmentedControl(items: ["Tap", "Clock", "Both"])
    private var timer: Timer?

    func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try POClockAudioUnit(componentDescription: componentDescription, options: [])
        audioUnit = unit
        if isViewLoaded { bindUI() }
        return unit
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 430, height: 600)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let title = UILabel()
        title.text = "PO CLOCK BRIDGE"
        title.font = .monospacedSystemFont(ofSize: 20, weight: .bold)
        title.textAlignment = .center

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 33, weight: .semibold)
        statusLabel.text = "— BPM"
        statusLabel.textAlignment = .center

        detailLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailLabel.numberOfLines = 2
        detailLabel.textAlignment = .center
        detailLabel.text = "SEARCHING"

        meter.progressTintColor = .systemGreen
        meter.trackTintColor = .secondarySystemFill

        configureSegmented(channelControl, identifier: "inputChannel")
        configureSegmented(ppqnControl, identifier: "inputPPQN")
        ppqnControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configureSegmented(outputControl, identifier: "outputMode")
        configureSwitch(autoThresholdSwitch, identifier: "autoThreshold")
        configureSwitch(transportSwitch, identifier: "transport")

        let resetButton = UIButton(type: .system)
        resetButton.setTitle("Phase Reset", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        resetButton.addTarget(self, action: #selector(resetPhase), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            title,
            statusLabel,
            detailLabel,
            meter,
            separator(),
            segmentedRow(title: "Clock channel", control: channelControl),
            segmentedRow(title: "Input PPQN", control: ppqnControl),
            switchRow(title: "Auto threshold", control: autoThresholdSwitch),
            sliderRow(title: "Threshold", identifier: "thresholdHigh",
                      slider: thresholdSlider, minimum: 0.02, maximum: 0.95),
            sliderRow(title: "Smoothing", identifier: "smoothing",
                      slider: smoothingSlider, minimum: 0.01, maximum: 1.0),
            sliderRow(title: "Phase correction", identifier: "phaseCorrection",
                      slider: phaseSlider, minimum: 0.0, maximum: 1.0),
            segmentedRow(title: "MIDI output", control: outputControl),
            switchRow(title: "Start / Stop", control: transportSwitch),
            resetButton
        ])
        stack.axis = .vertical
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -18),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
            meter.heightAnchor.constraint(equalToConstant: 8)
        ])

        bindUI()
    }

    private func separator() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return line
    }

    private func label(_ text: String) -> UILabel {
        let result = UILabel()
        result.text = text
        result.font = .systemFont(ofSize: 13, weight: .medium)
        result.widthAnchor.constraint(equalToConstant: 112).isActive = true
        return result
    }

    private func configureSegmented(_ control: UISegmentedControl, identifier: String) {
        control.accessibilityIdentifier = identifier
        control.addTarget(self, action: #selector(segmentedChanged(_:)), for: .valueChanged)
        control.selectedSegmentIndex = 0
    }

    private func configureSwitch(_ control: UISwitch, identifier: String) {
        control.accessibilityIdentifier = identifier
        control.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
    }

    private func segmentedRow(title: String, control: UISegmentedControl) -> UIView {
        let row = UIStackView(arrangedSubviews: [label(title), control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        return row
    }

    private func switchRow(title: String, control: UISwitch) -> UIView {
        let spacer = UIView()
        let row = UIStackView(arrangedSubviews: [label(title), spacer, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        return row
    }

    private func sliderRow(title: String,
                           identifier: String,
                           slider: UISlider,
                           minimum: Float,
                           maximum: Float) -> UIView {
        slider.minimumValue = minimum
        slider.maximumValue = maximum
        slider.accessibilityIdentifier = identifier
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [label(title), slider])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        return row
    }

    private func parameter(_ identifier: String) -> AUParameter? {
        audioUnit?.parameterTree?.parameter(withID: identifier)
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        guard let identifier = sender.accessibilityIdentifier else { return }
        parameter(identifier)?.value = AUValue(sender.value)
    }

    @objc private func segmentedChanged(_ sender: UISegmentedControl) {
        guard let identifier = sender.accessibilityIdentifier else { return }
        parameter(identifier)?.value = AUValue(sender.selectedSegmentIndex)
    }

    @objc private func switchChanged(_ sender: UISwitch) {
        guard let identifier = sender.accessibilityIdentifier else { return }
        parameter(identifier)?.value = sender.isOn ? 1.0 : 0.0
        if sender === autoThresholdSwitch {
            thresholdSlider.isEnabled = !sender.isOn
        }
    }

    @objc private func resetPhase() {
        audioUnit?.resetClockPhase()
    }

    private func bindUI() {
        timer?.invalidate()
        guard let audioUnit else { return }

        thresholdSlider.value = Float(parameter("thresholdHigh")?.value ?? 0.30)
        smoothingSlider.value = Float(parameter("smoothing")?.value ?? 0.18)
        phaseSlider.value = Float(parameter("phaseCorrection")?.value ?? 0.30)
        channelControl.selectedSegmentIndex = Int(parameter("inputChannel")?.value ?? 0)
        ppqnControl.selectedSegmentIndex = Int(parameter("inputPPQN")?.value ?? 2)
        outputControl.selectedSegmentIndex = Int(parameter("outputMode")?.value ?? 2)
        autoThresholdSwitch.isOn = (parameter("autoThreshold")?.value ?? 1) >= 0.5
        transportSwitch.isOn = (parameter("transport")?.value ?? 1) >= 0.5
        thresholdSlider.isEnabled = !autoThresholdSwitch.isOn

        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) {
            [weak self, weak audioUnit] _ in
            guard let self, let audioUnit else { return }
            let bpm = audioUnit.detectedBPM
            self.statusLabel.text = bpm > 1 ? String(format: "%.2f BPM", bpm) : "— BPM"
            if audioUnit.isLocked {
                self.detailLabel.text = String(
                    format: "LOCKED • PPQN %.0f • jitter %.2f ms\nphase %+.2f ms • pulses %llu",
                    audioUnit.effectiveInputPPQN,
                    audioUnit.jitterMs,
                    audioUnit.phaseErrorMs,
                    audioUnit.pulseCount)
            } else {
                self.detailLabel.text = String(
                    format: "SEARCHING • peak %.3f\nthreshold %.3f",
                    audioUnit.inputPeak,
                    audioUnit.effectiveThreshold)
            }
            self.meter.setProgress(min(1.0, audioUnit.inputPeak), animated: true)
        }
    }

    deinit {
        timer?.invalidate()
    }
}
