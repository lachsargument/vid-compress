import Foundation

struct OutputFormat {
    let title: String
    let ext: String
    let codec: [String]
    let audio: [String]
    /// CRF for high / medium / low quality; scales differ per encoder.
    let crf: [Int]
    /// VideoToolbox encoder arguments, or nil if there is no hardware encoder.
    var hardwareCodec: [String]? = nil
}

/// VideoToolbox -q:v for high / medium / low quality (0-100, higher is
/// better). VideoToolbox has no CRF, and -q:v works on Apple Silicon only.
// ponytail: rough values picked to sit near the software CRF defaults;
// tune them against real footage if the sizes look off.
let hardwareQuality = [65, 55, 45]

let aacAudio = ["-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"]

let formats = [
    OutputFormat(
        title: "MP4 · H.264", ext: "mp4",
        codec: ["-c:v", "libx264", "-preset", "medium", "-pix_fmt", "yuv420p"],
        audio: aacAudio, crf: [20, 23, 28],
        hardwareCodec: ["-c:v", "h264_videotoolbox", "-pix_fmt", "yuv420p"]),
    // hvc1 tag: QuickTime and iOS refuse HEVC tagged as the default hev1.
    OutputFormat(
        title: "MP4 · HEVC", ext: "mp4",
        codec: ["-c:v", "libx265", "-preset", "medium", "-tag:v", "hvc1", "-pix_fmt", "yuv420p"],
        audio: aacAudio, crf: [22, 26, 30],
        hardwareCodec: ["-c:v", "hevc_videotoolbox", "-tag:v", "hvc1", "-pix_fmt", "yuv420p"]),
    // -b:v 0 switches libvpx-vp9 into constant-quality mode so -crf applies.
    OutputFormat(
        title: "WebM · VP9", ext: "webm",
        codec: ["-c:v", "libvpx-vp9", "-b:v", "0", "-row-mt", "1", "-pix_fmt", "yuv420p"],
        audio: ["-c:a", "libopus", "-b:a", "96k"], crf: [28, 33, 38]),
]

let frameRates: [Int?] = [nil, 60, 30, 25, 24, 15]
let resolutions: [Int?] = [nil, 2160, 1440, 1080, 720, 480, 360]
let qualities = ["High", "Medium", "Low"]

/// Builds ffmpeg arguments. `shortSide` caps the shorter edge ("720p"
/// means 720 tall for landscape, 720 wide for portrait) and never
/// upscales. `hardware` uses the VideoToolbox encoder when the format
/// has one. Progress goes to stdout as key=value lines.
func ffmpegArgs(
    input: String, output: String, format: OutputFormat, fps: Int?, shortSide: Int?,
    quality: Int, hardware: Bool = false
) -> [String] {
    var filters: [String] = []
    if let fps { filters.append("fps=\(fps)") }
    if let s = shortSide {
        filters.append(
            "scale='if(gt(iw,ih),-2,min(\(s),iw))':'if(gt(iw,ih),min(\(s),ih),-2)'")
    }
    // Hardware decoding is always on. If VideoToolbox cannot decode the
    // input codec, FFmpeg falls back to software decoding by itself.
    var args = [
        "-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-hwaccel", "videotoolbox",
        "-i", input,
    ]
    if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }
    if hardware, let codec = format.hardwareCodec {
        args += codec + ["-q:v", String(hardwareQuality[quality])]
    } else {
        args += format.codec + ["-crf", String(format.crf[quality])]
    }
    args += format.audio
    return args + ["-progress", "pipe:1", "-nostats", output]
}

/// GUI apps don't inherit the shell PATH, so check Homebrew's locations too.
func findTool(_ name: String) -> URL? {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let dirs =
        ["/opt/homebrew/bin", "/usr/local/bin"] + path.split(separator: ":").map(String.init)
    return dirs.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
}

/// Duration in seconds via ffprobe, or nil if unknown.
func probeDuration(_ ffprobe: URL, _ input: String) -> Double? {
    let proc = Process()
    proc.executableURL = ffprobe
    proc.arguments = [
        "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", input,
    ]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    guard (try? proc.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    return Double(
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}
