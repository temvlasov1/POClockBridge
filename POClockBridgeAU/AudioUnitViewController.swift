import AudioToolbox
import CoreAudioKit
import Dispatch
import Foundation
import UIKit

final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private var audioUnit: POClockAudioUnit?
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let thresholdSlider = UISlider()
    private let smoothingSlider = UISlider()
    private let phaseSlider = UISlider()
    private let autoThresholdSwitch = UISwitch()
    private let transportSwitch = UISwitch()
    private let channelControl = UISegmentedControl(items: ["L", "R"])
    private let ppqnControl = UISegmentedControl(items: ["Auto", "1", "2", "4", "12", "24", "48"])
    private let outputControl = UISegmentedControl(items: ["Tap", "Clock", "Both"])
    func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try POClockAudioUnit(componentDescription: componentDescription, options: [])
        audioUnit = unit
        // Hosts are allowed to instantiate an Audio Unit away from the main
        // thread. Even reading view lifecycle state must stay on main.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isViewLoaded else { return }
            self.bindUI()
        }
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
        title.text = "PO CLOCK BRIDGE • 0.3"
        title.font = .monospacedSystemFont(ofSize: 20, weight: .bold)
        title.textAlignment = .center

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 33, weight: .semibold)
        statusLabel.text = "READY"
        statusLabel.textAlignment = .center

        detailLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailLabel.numberOfLines = 2
        detailLabel.textAlignment = .center
        detailLabel.text = "BUILD 6 • STABLE UI\nClock detection runs in the audio engine"

        let refreshButton = UIButton(type: .system)
        refreshButton.setTitle("Refresh BPM (manual)", for: .normal)
        refreshButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        refreshButton.addTarget(self, action: #selector(refreshStatus), for: .touchUpInside)

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
            refreshButton,
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
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
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
        audioUnit?.parameterTree?.allParameters.first { $0.identifier == identifier }
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

    @objc private func refreshStatus() {
        guard let audioUnit else {
            statusLabel.text = "WAITING"
            detailLabel.text = "Audio Unit is not connected yet"
            return
        }

        let measuredBPM = Double(audioUnit.detectedBPM)
        guard measuredBPM > 1 else {
            statusLabel.text = "— BPM"
            detailLabel.text = "WAITING FOR CLOCK • tap Refresh after two pulses"
            return
        }

        // Pocket Operator shows a nominal integer tempo, while the physical
        // sync oscillator can be a few tenths away. Present the nominal value
        // when it is unambiguous, but keep the measured period in the engine:
        // quantizing MIDI scheduling itself would create long-term drift.
        let nearestInteger = measuredBPM.rounded()
        let isNominalInteger = abs(measuredBPM - nearestInteger) <= 0.75
        statusLabel.text = isNominalInteger
            ? String(format: "%.0f BPM", nearestInteger)
            : String(format: "%.2f BPM", measuredBPM)
        detailLabel.text = String(
            format: "MEASURED %.2f • jitter %.2f ms\nMIDI clock follows the physical input",
            measuredBPM,
            audioUnit.jitterMs)
    }

    private func bindUI() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard audioUnit != nil else { return }

        thresholdSlider.value = Float(parameter("thresholdHigh")?.value ?? 0.30)
        smoothingSlider.value = Float(parameter("smoothing")?.value ?? 0.18)
        phaseSlider.value = Float(parameter("phaseCorrection")?.value ?? 0.30)
        channelControl.selectedSegmentIndex = Int(parameter("inputChannel")?.value ?? 0)
        ppqnControl.selectedSegmentIndex = Int(parameter("inputPPQN")?.value ?? 2)
        outputControl.selectedSegmentIndex = Int(parameter("outputMode")?.value ?? 2)
        autoThresholdSwitch.isOn = (parameter("autoThreshold")?.value ?? 1) >= 0.5
        transportSwitch.isOn = (parameter("transport")?.value ?? 1) >= 0.5
        thresholdSlider.isEnabled = !autoThresholdSwitch.isOn
    }
}
