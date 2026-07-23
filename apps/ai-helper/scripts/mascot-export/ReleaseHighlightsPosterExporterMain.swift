import AppKit
import Foundation
import SwiftUI

@MainActor
@main
struct ReleaseHighlightsPosterExporterMain {
    static func main() throws {
        let options = try PosterOptions(arguments: Array(CommandLine.arguments.dropFirst()))
        try options.prepareOutputDirectory()

        let outputURL = options.outputDirectory.appendingPathComponent(options.outputName)
        let posterView = ReleaseHighlightsPosterView(options: options)
            .frame(width: options.canvasSize.width, height: options.canvasSize.height)

        let renderer = ImageRenderer(content: posterView)
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.proposedSize = .init(width: options.canvasSize.width, height: options.canvasSize.height)

        guard let cgImage = renderer.cgImage else {
            throw PosterExportError.failedToRender(outputURL.path)
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw PosterExportError.failedToEncode(outputURL.path)
        }

        try data.write(to: outputURL, options: .atomic)
        print("wrote \(outputURL.path)")
    }
}

private struct PosterOptions {
    let outputDirectory: URL
    let outputName: String
    let canvasSize: CGSize
    let iconURL: URL
    let codeBuddyIconURL: URL
    let workBuddyIconURL: URL
    let notchPreviewURL: URL
    let questionPreviewURL: URL
    let variant: PosterVariant

    init(arguments: [String]) throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        var outputDirectory = cwd.appendingPathComponent("docs/images", isDirectory: true)
        var outputName = "ai-helper-release-highlights.png"
        var width = 2800
        var height = 1800
        var iconURL = cwd.appendingPathComponent("AIHelper/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png")
        var codeBuddyIconURL = cwd.appendingPathComponent("docs/images/product-icons/codebuddy-app-icon.png")
        var workBuddyIconURL = cwd.appendingPathComponent("docs/images/product-icons/workbuddy-app-icon.png")
        var notchPreviewURL = cwd.appendingPathComponent("docs/images/notch-panel.png")
        var questionPreviewURL = cwd.appendingPathComponent("docs/images/question-panel.png")
        var variant = PosterVariant.remoteWorkflows

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--output-dir":
                index += 1
                outputDirectory = URL(
                    fileURLWithPath: try Self.value(after: argument, at: index, in: arguments),
                    isDirectory: true
                )
            case "--output-name":
                index += 1
                outputName = try Self.value(after: argument, at: index, in: arguments)
            case "--width":
                index += 1
                width = try Self.intValue(after: argument, at: index, in: arguments)
            case "--height":
                index += 1
                height = try Self.intValue(after: argument, at: index, in: arguments)
            case "--icon":
                index += 1
                iconURL = URL(fileURLWithPath: try Self.value(after: argument, at: index, in: arguments))
            case "--codebuddy-icon":
                index += 1
                codeBuddyIconURL = URL(fileURLWithPath: try Self.value(after: argument, at: index, in: arguments))
            case "--workbuddy-icon":
                index += 1
                workBuddyIconURL = URL(fileURLWithPath: try Self.value(after: argument, at: index, in: arguments))
            case "--notch-preview":
                index += 1
                notchPreviewURL = URL(fileURLWithPath: try Self.value(after: argument, at: index, in: arguments))
            case "--question-preview":
                index += 1
                questionPreviewURL = URL(fileURLWithPath: try Self.value(after: argument, at: index, in: arguments))
            case "--variant":
                index += 1
                variant = try PosterVariant(rawValue: Self.value(after: argument, at: index, in: arguments))
            case "--help", "-h":
                throw PosterExportError.helpText
            default:
                throw PosterExportError.unknownArgument(argument)
            }
            index += 1
        }

        guard width > 0, height > 0 else {
            throw PosterExportError.invalidValue("canvas", "\(width)x\(height)")
        }

        self.outputDirectory = outputDirectory
        self.outputName = outputName
        self.canvasSize = CGSize(width: width, height: height)
        self.iconURL = iconURL
        self.codeBuddyIconURL = codeBuddyIconURL
        self.workBuddyIconURL = workBuddyIconURL
        self.notchPreviewURL = notchPreviewURL
        self.questionPreviewURL = questionPreviewURL
        self.variant = variant
    }

    func prepareOutputDirectory() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    private static func value(after flag: String, at index: Int, in arguments: [String]) throws -> String {
        guard arguments.indices.contains(index) else {
            throw PosterExportError.missingValue(flag)
        }
        return arguments[index]
    }

    private static func intValue(after flag: String, at index: Int, in arguments: [String]) throws -> Int {
        let raw = try value(after: flag, at: index, in: arguments)
        guard let value = Int(raw) else {
            throw PosterExportError.invalidValue(flag, raw)
        }
        return value
    }
}

private enum PosterVariant: String {
    case remoteWorkflows = "remote-workflows"
    case smoothUpdates = "smooth-updates"
    case v010Chinese = "v0.1.0-cn"
    case v011CodeBuddyWorkBuddyChinese = "v0.1.1-codebuddy-workbuddy-cn"

    init(rawValue: String) throws {
        guard let value = PosterVariant(rawValue: rawValue) else {
            throw PosterExportError.invalidValue("--variant", rawValue)
        }
        self = value
    }
}

private enum PosterExportError: LocalizedError {
    case missingValue(String)
    case invalidValue(String, String)
    case unknownArgument(String)
    case failedToRender(String)
    case failedToEncode(String)
    case helpText

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        case .invalidValue(let flag, let value):
            return "Invalid value for \(flag): \(value)"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        case .failedToRender(let path):
            return "Failed to render poster for \(path)"
        case .failedToEncode(let path):
            return "Failed to encode PNG for \(path)"
        case .helpText:
            return """
            Usage: render-release-highlights-posters.sh [options]

              --output-dir <path>        Output directory (default: docs/images)
              --output-name <name>       Output filename
              --width <pixels>           Canvas width (default: 2800)
              --height <pixels>          Canvas height (default: 1800)
              --icon <path>              App icon path
              --codebuddy-icon <path>    CodeBuddy product icon path
              --workbuddy-icon <path>    WorkBuddy product icon path
              --notch-preview <path>     Notch preview image path
              --question-preview <path>  Question preview image path
              --variant <name>           remote-workflows | smooth-updates | v0.1.0-cn | v0.1.1-codebuddy-workbuddy-cn
            """
        }
    }
}

private struct ReleaseHighlightsPosterView: View {
    let options: PosterOptions

    var body: some View {
        switch options.variant {
        case .remoteWorkflows:
            RemoteWorkflowsPoster(options: options)
        case .smoothUpdates:
            SmoothUpdatesPoster(options: options)
        case .v010Chinese:
            V010ChinesePoster(options: options)
        case .v011CodeBuddyWorkBuddyChinese:
            V011CodeBuddyWorkBuddyChinesePoster(options: options)
        }
    }
}

private struct RemoteWorkflowsPoster: View {
    let options: PosterOptions

    private let featureRows = [
        "SSH terminals surface back in your local Island UI",
        "OpenClaw now backfills real conversation history",
        "OpenCode plugin loading and approvals are reliable again",
        "One menu bar lane for Claude Code, Codex, OpenClaw, and OpenCode",
    ]

    var body: some View {
        ZStack {
            SharedPosterBackground(
                topGlow: Color(red: 0.99, green: 0.61, blue: 0.24),
                bottomGlow: Color(red: 0.26, green: 0.57, blue: 0.97)
            )

            VStack(spacing: 46) {
                PosterHeader(
                    iconURL: options.iconURL,
                    eyebrow: "AI-HELPER 0.0.5 -> 0.0.9",
                    title: "Remote workflows, one Island.",
                    subtitle: "SSH sessions, OpenClaw transcripts, and OpenCode recovery all land in a clearer multi-client flow."
                )

                HStack(alignment: .top, spacing: 34) {
                    BigFeatureCard(
                        title: "Workflow upgrades",
                        bullets: featureRows,
                        accent: Color(red: 0.99, green: 0.61, blue: 0.24)
                    )

                    VStack(spacing: 28) {
                        PreviewCard(
                            title: "Local Island view",
                            caption: "Remote approvals, follow-ups, and completions still show up in the same native surface.",
                            imageURL: options.notchPreviewURL,
                            accent: Color(red: 0.99, green: 0.72, blue: 0.31)
                        )

                        MascotStripCard(
                            title: "Clients now moving together",
                            subtitle: "Claude Code, Codex, OpenClaw, and OpenCode all got sharper monitoring paths.",
                            mascots: [
                                (.claude, .working),
                                (.codex, .working),
                                (.openclaw, .warning),
                                (.opencode, .working),
                            ],
                            accent: Color(red: 0.30, green: 0.66, blue: 0.98)
                        )
                    }
                    .frame(width: 920)
                }

                PosterFooter(tags: [
                    "SSH bridge bootstrapping",
                    "Transcript backfill",
                    "Plugin runtime fixes",
                    "Cross-client visibility",
                ])
            }
            .padding(.horizontal, 106)
            .padding(.vertical, 88)
        }
    }
}

private struct SmoothUpdatesPoster: View {
    let options: PosterOptions

    private let featureRows = [
        "Message queue and session list updates feel less jumpy",
        "Idle heartbeats no longer knock active work back too early",
        "Online release notes survive missing Markdown sources better",
        "Update windows, shortcuts, and settings reopening feel cleaner",
    ]

    var body: some View {
        ZStack {
            SharedPosterBackground(
                topGlow: Color(red: 0.19, green: 0.79, blue: 0.71),
                bottomGlow: Color(red: 0.98, green: 0.53, blue: 0.19)
            )

            VStack(spacing: 46) {
                PosterHeader(
                    iconURL: options.iconURL,
                    eyebrow: "AI-HELPER 0.0.5 -> 0.0.9",
                    title: "Smoother updates, calmer status.",
                    subtitle: "Queue behavior, release notes, update UX, and window details all got a steady polish pass."
                )

                HStack(alignment: .top, spacing: 34) {
                    VStack(spacing: 28) {
                        BigFeatureCard(
                            title: "Experience polish",
                            bullets: featureRows,
                            accent: Color(red: 0.19, green: 0.79, blue: 0.71)
                        )

                        MascotStripCard(
                            title: "Less jitter, better rhythm",
                            subtitle: "Active sessions hold their place, and the UI tells a clearer story while agents keep running.",
                            mascots: [
                                (.codex, .working),
                                (.gemini, .idle),
                                (.cursor, .working),
                                (.copilot, .warning),
                            ],
                            accent: Color(red: 0.98, green: 0.53, blue: 0.19)
                        )
                    }

                    VStack(spacing: 28) {
                        PreviewCard(
                            title: "Questions stay readable",
                            caption: "Update notes and interactive prompts have safer fallbacks and better presentation.",
                            imageURL: options.questionPreviewURL,
                            accent: Color(red: 0.22, green: 0.63, blue: 0.97)
                        )

                        MetricBoardCard()
                    }
                    .frame(width: 920)
                }

                PosterFooter(tags: [
                    "Queue smoothing",
                    "Idle-heartbeat guardrails",
                    "Release-note fallback",
                    "Update UX polish",
                ])
            }
            .padding(.horizontal, 106)
            .padding(.vertical, 88)
        }
    }
}

private struct V010ChinesePoster: View {
    let options: PosterOptions

    private let featureRows = [
        "合并 0.0.5 到 0.0.9 的重点能力升级",
        "SSH 远程终端监控更完整",
        "远程会话可更稳定回流本机",
        "OpenClaw 支持消息内容回填",
        "OpenCode 集成链路更成熟",
        "消息队列与状态更新更顺滑",
        "在线 release notes 展示更稳定",
        "更新窗口与交互细节继续打磨",
        "现已正式支持自动更新",
    ]

    var body: some View {
        ZStack {
            SharedPosterBackground(
                topGlow: Color(red: 0.99, green: 0.60, blue: 0.24),
                bottomGlow: Color(red: 0.18, green: 0.77, blue: 0.70)
            )

            VStack(spacing: 44) {
                PosterHeader(
                    iconURL: options.iconURL,
                    eyebrow: "AI-HELPER VERSION 0.1.0",
                    title: "0.1.0 版本更新日志",
                    subtitle: "这是一次里程碑整合发布：把 0.0.5 到 0.0.9 的关键优化合并进来，并正式带来自动更新能力。"
                )

                HStack(alignment: .top, spacing: 34) {
                    VStack(spacing: 28) {
                        BigFeatureCard(
                            title: "本次重点",
                            bullets: featureRows,
                            accent: Color(red: 0.99, green: 0.60, blue: 0.24),
                            minHeight: 690
                        )

                        HStack(spacing: 22) {
                            ChineseMilestoneCard()
                            ChineseKeywordsCard()
                        }
                    }

                    VStack(spacing: 28) {
                        PreviewCard(
                            title: "更新后的 Island",
                            caption: "多客户端会话、远程 SSH 工作流与更新提示体验，都在这一版收口到更完整的一套产品节奏里。",
                            imageURL: options.notchPreviewURL,
                            accent: Color(red: 0.24, green: 0.63, blue: 0.98)
                        )

                        MascotStripCard(
                            title: "多客户端统一收口",
                            subtitle: "Claude Code、Codex、OpenClaw 与 OpenCode 的监控体验在 0.1.0 一起进入新阶段。",
                            mascots: [
                                (.claude, .working),
                                (.codex, .working),
                                (.openclaw, .warning),
                                (.opencode, .working),
                            ],
                            accent: Color(red: 0.18, green: 0.77, blue: 0.70)
                        )
                    }
                    .frame(width: 920)
                }

                PosterFooter(tags: [
                    "0.0.5 -> 0.0.9 合并",
                    "SSH 远程支持",
                    "集成链路补强",
                    "自动更新上线",
                ])
            }
            .padding(.horizontal, 106)
            .padding(.vertical, 88)
        }
    }
}

private struct V011CodeBuddyWorkBuddyChinesePoster: View {
    let options: PosterOptions

    private let featureRows = [
        "0.1.1 重点补强 CodeBuddy 与 WorkBuddy 监控",
        "WorkBuddy 现在作为独立客户端画像接入 Island",
        "客户端内追问改成 external-only 展示，不再误导成可在 Island 内直接提交",
        "回答完成后会继续等待客户端续跑，并提供一键打开客户端回到现场",
        "CodeBuddy / WorkBuddy 的历史记录支持按 index.json 做增量回填",
        "用户 query 文本会从包裹字段里提纯，列表与 hover 里的内容更干净",
    ]

    var body: some View {
        ZStack {
            SharedPosterBackground(
                topGlow: Color(red: 0.43, green: 0.38, blue: 0.98),
                bottomGlow: Color(red: 0.12, green: 0.78, blue: 0.62)
            )

            VStack(spacing: 44) {
                PosterHeader(
                    iconURL: options.iconURL,
                    eyebrow: "AI-HELPER VERSION 0.1.1",
                    title: "CodeBuddy / WorkBuddy 监控优化",
                    subtitle: "这一版把两个客户端的识别、追问状态、客户端回跳和历史回填都重新梳顺，让 Island 对它们的监控更像“正式支持”，而不是兼容兜底。"
                )

                HStack(alignment: .top, spacing: 34) {
                    VStack(spacing: 28) {
                        BigFeatureCard(
                            title: "本次重点",
                            bullets: featureRows,
                            accent: Color(red: 0.43, green: 0.38, blue: 0.98),
                            minHeight: 760,
                            bulletFontSize: 44
                        )

                        HStack(spacing: 22) {
                            MonitoringPositionCard()
                            MonitoringKeywordsCard()
                        }
                    }

                    VStack(spacing: 28) {
                        PreviewCard(
                            title: "提问状态更准确",
                            caption: "当 CodeBuddy / WorkBuddy 在客户端内发起 follow-up question 时，Island 会明确提示切回客户端完成回答，并保留更自然的续跑节奏。",
                            imageURL: options.questionPreviewURL,
                            accent: Color(red: 0.19, green: 0.68, blue: 0.98)
                        )

                        ClientProductPairCard(
                            title: "客户端画像更完整",
                            subtitle: "CodeBuddy 与 WorkBuddy 现在都能以更清楚的品牌与交互路径出现在监控面板里。",
                            accent: Color(red: 0.12, green: 0.78, blue: 0.62),
                            clients: [
                                ClientPosterIdentity(
                                    title: "CodeBuddy",
                                    subtitle: "追问回跳\n历史回填",
                                    imageURL: options.codeBuddyIconURL
                                ),
                                ClientPosterIdentity(
                                    title: "WorkBuddy",
                                    subtitle: "独立识别\n外部续跑",
                                    imageURL: options.workBuddyIconURL
                                ),
                            ]
                        )
                    }
                    .frame(width: 920)
                }

                PosterFooter(tags: [
                    "独立客户端识别",
                    "follow-up 状态修正",
                    "一键打开客户端",
                    "历史增量回填",
                ])
            }
            .padding(.horizontal, 106)
            .padding(.vertical, 88)
        }
    }
}

private struct SharedPosterBackground: View {
    let topGlow: Color
    let bottomGlow: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.97, blue: 0.92),
                    Color(red: 0.95, green: 0.94, blue: 0.90),
                    Color(red: 0.92, green: 0.91, blue: 0.88),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(topGlow.opacity(0.18))
                .frame(width: 860, height: 860)
                .blur(radius: 24)
                .offset(x: -720, y: -440)

            Circle()
                .fill(bottomGlow.opacity(0.16))
                .frame(width: 920, height: 920)
                .blur(radius: 30)
                .offset(x: 760, y: 500)

            RoundedRectangle(cornerRadius: 120, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 2)
                .padding(24)
        }
    }
}

private struct PosterHeader: View {
    let iconURL: URL
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 50) {
            PosterAppIcon(iconURL: iconURL)

            VStack(alignment: .leading, spacing: 18) {
                Text(eyebrow)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .tracking(3.5)
                    .foregroundStyle(Color(red: 0.56, green: 0.47, blue: 0.34))

                Text(title)
                    .font(.system(size: 130, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.14, green: 0.12, blue: 0.10))
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 35, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.30))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct PosterAppIcon: View {
    let iconURL: URL

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            Color.white.opacity(0.12),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .frame(width: 360, height: 360)

            RoundedRectangle(cornerRadius: 82, style: .continuous)
                .fill(.white.opacity(0.44))
                .overlay(
                    RoundedRectangle(cornerRadius: 82, style: .continuous)
                        .stroke(.white.opacity(0.92), lineWidth: 2)
                )
                .frame(width: 292, height: 292)
                .shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: 12)

            if let iconImage = loadedImage(from: iconURL) {
                iconImage
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 226, height: 226)
                    .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
            }
        }
        .frame(width: 360, height: 360)
    }
}

private struct BigFeatureCard: View {
    let title: String
    let bullets: [String]
    let accent: Color
    var minHeight: CGFloat = 920
    var bulletFontSize: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            CardLabel(text: title, accent: accent)

            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 16) {
                    Circle()
                        .fill(accent)
                        .frame(width: 14, height: 14)
                        .padding(.top, 14)

                    Text(bullet)
                        .font(.system(size: bulletFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.18, green: 0.15, blue: 0.12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .padding(38)
        .background(PosterCardBackground())
    }
}

private struct PreviewCard: View {
    let title: String
    let caption: String
    let imageURL: URL
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CardLabel(text: title, accent: accent)

            if let preview = loadedImage(from: imageURL) {
                preview
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.75), lineWidth: 1.5)
                    )
            }

            Text(caption)
                .font(.system(size: 29, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.38, green: 0.33, blue: 0.28))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(30)
        .background(PosterCardBackground())
    }
}

private struct MascotStripCard: View {
    let title: String
    let subtitle: String
    let mascots: [(MascotKind, MascotStatus)]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CardLabel(text: title, accent: accent)

            Text(subtitle)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.37, green: 0.32, blue: 0.28))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                ForEach(Array(mascots.enumerated()), id: \.offset) { _, mascot in
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.white.opacity(0.76))
                                .frame(width: 170, height: 170)

                            MascotView(kind: mascot.0, status: mascot.1, size: 120, animationTime: 0.8)
                        }

                        Text(mascot.0.title)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.19, green: 0.16, blue: 0.13))
                    }
                }
            }
        }
        .padding(30)
        .background(PosterCardBackground())
    }
}

private struct MetricBoardCard: View {
    private let rows = [
        ("Queue", "Smoother list motion"),
        ("Idle", "Fewer false sleeps"),
        ("Notes", "Better fallback coverage"),
        ("Windows", "Cleaner reopen behavior"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CardLabel(text: "Quality pass", accent: Color(red: 0.98, green: 0.53, blue: 0.19))

            ForEach(rows, id: \.0) { row in
                HStack(spacing: 18) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.15, green: 0.16, blue: 0.18))
                        .frame(width: 140, height: 74)
                        .overlay(
                            Text(row.0)
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        )

                    Text(row.1)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.19, green: 0.16, blue: 0.13))

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(30)
        .background(PosterCardBackground())
    }
}

private struct ChineseMilestoneCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CardLabel(text: "版本定位", accent: Color(red: 0.99, green: 0.60, blue: 0.24))

            Text("0.1.0 是一次里程碑整合发布。")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.18, green: 0.15, blue: 0.12))
                .fixedSize(horizontal: false, vertical: true)

            Text("把此前几版分散落地的远程监控、客户端集成、状态流畅度和更新体验，收口进一版更完整的正式可用体验。")
                .font(.system(size: 27, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.38, green: 0.33, blue: 0.28))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .padding(30)
        .background(PosterCardBackground())
    }
}

private struct ChineseKeywordsCard: View {
    private let tags = [
        "远程 SSH",
        "OpenClaw",
        "OpenCode",
        "状态更丝滑",
        "在线说明",
        "自动更新",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CardLabel(text: "关键词", accent: Color(red: 0.18, green: 0.77, blue: 0.70))

            Text("这一版的更新核心")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.18, green: 0.15, blue: 0.12))

            FlowTagCloud(tags: tags)
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .padding(30)
        .background(PosterCardBackground())
    }
}

private struct MonitoringPositionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CardLabel(text: "版本定位", accent: Color(red: 0.43, green: 0.38, blue: 0.98))

            Text("0.1.1 是一次针对客户端监控质量的补强。")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.18, green: 0.15, blue: 0.12))
                .fixedSize(horizontal: false, vertical: true)

            Text("不是简单地“多认出两个名字”，而是把 CodeBuddy / WorkBuddy 的真实交互节奏重新映射到 Island，让提问、续跑、跳转和消息回填更贴近客户端本身。")
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.38, green: 0.33, blue: 0.28))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .padding(30)
        .background(PosterCardBackground())
    }
}

private struct MonitoringKeywordsCard: View {
    private let tags = [
        "CodeBuddy",
        "WorkBuddy",
        "follow-up question",
        "外部续跑",
        "打开客户端",
        "history index",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CardLabel(text: "关键词", accent: Color(red: 0.12, green: 0.78, blue: 0.62))

            Text("这一版的核心变化")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.18, green: 0.15, blue: 0.12))

            FlowTagCloud(tags: tags)
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .padding(30)
        .background(PosterCardBackground())
    }
}

private struct ClientPosterIdentity {
    let title: String
    let subtitle: String
    let imageURL: URL
}

private struct ClientProductPairCard: View {
    let title: String
    let subtitle: String
    let accent: Color
    let clients: [ClientPosterIdentity]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CardLabel(text: title, accent: accent)

            Text(subtitle)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.37, green: 0.32, blue: 0.28))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                ForEach(Array(clients.enumerated()), id: \.offset) { _, client in
                    ClientProductTile(client: client)
                }
            }
        }
        .padding(30)
        .background(PosterCardBackground())
    }
}

private struct ClientProductTile: View {
    let client: ClientPosterIdentity

    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.white.opacity(0.76))
                .frame(maxWidth: .infinity, minHeight: 194)
                .overlay {
                    if let image = loadedImage(from: client.imageURL) {
                        image
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 124, height: 124)
                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    }
                }

            Text(client.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.19, green: 0.16, blue: 0.13))

            Text(client.subtitle)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.40, green: 0.34, blue: 0.29))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct PosterFooter: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.27, green: 0.24, blue: 0.20))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.72))
                    )
            }
            Spacer(minLength: 0)
        }
    }
}

private struct FlowTagCloud: View {
    let tags: [String]

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.23, green: 0.20, blue: 0.17))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.78))
                    )
            }
        }
    }
}

private struct CardLabel: View {
    let text: String
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accent)
                .frame(width: 16, height: 16)

            Text(text.uppercased())
                .font(.system(size: 24, weight: .black, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(Color(red: 0.49, green: 0.42, blue: 0.35))
        }
    }
}

private struct PosterCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 40, style: .continuous)
            .fill(.white.opacity(0.60))
            .overlay(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .stroke(Color.white.opacity(0.86), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 10)
    }
}

private func loadedImage(from url: URL) -> Image? {
    guard let image = NSImage(contentsOf: url) else { return nil }
    return Image(nsImage: image)
}
