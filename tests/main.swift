// Self-check for Core.swift: encodes a portrait test clip with every
// format and checks the output size/fps via ffprobe. Run via ./test.sh.
import Foundation

func check(_ ok: Bool, _ what: String) {
    if !ok {
        print("FAIL: \(what)")
        exit(1)
    }
}

func run(_ tool: URL, _ args: [String]) -> (Int32, String) {
    let p = Process()
    p.executableURL = tool
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    try! p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

let dir = CommandLine.arguments[1]
let ffmpeg = findTool("ffmpeg")!
let ffprobe = findTool("ffprobe")!
let input = "\(dir)/portrait.mp4"
_ = run(
    ffmpeg,
    [
        "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
        "testsrc=size=1080x1920:rate=60:duration=2", "-f", "lavfi", "-i",
        "sine=duration=2", "-shortest", input,
    ])
check(abs((probeDuration(ffprobe, input) ?? 0) - 2) < 0.1, "probe duration")

let runs =
    formats.map { ($0, false) } + formats.filter { $0.hardwareCodec != nil }.map { ($0, true) }
for (format, hardware) in runs {
    let output = "\(dir)/out.\(format.ext)"
    let args = ffmpegArgs(
        input: input, output: output, format: format, fps: 24, shortSide: 720, quality: 1,
        hardware: hardware)
    let name = "\(format.title)\(hardware ? " (hardware)" : "")"
    check(args.contains(hardware ? format.hardwareCodec![1] : format.codec[1]), "\(name) encoder")
    let (status, progress) = run(ffmpeg, args)
    check(status == 0, "\(name) encode")
    check(progress.contains("out_time_us="), "\(name) progress output")
    let (_, info) = run(
        ffprobe,
        [
            "-v", "error", "-select_streams", "v:0", "-show_entries",
            "stream=width,height,r_frame_rate", "-of", "csv=p=0", output,
        ])
    check(
        info.trimmingCharacters(in: .whitespacesAndNewlines) == "720,1280,24/1",
        "\(name) got \(info)")
}

// no options: no filter, never upscales
let plain = ffmpegArgs(
    input: "a", output: "b", format: formats[0], fps: nil, shortSide: nil, quality: 0)
check(!plain.contains("-vf") && plain.contains("20"), "plain args")

print("all checks passed")
