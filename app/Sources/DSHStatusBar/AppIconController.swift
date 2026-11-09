import AppKit
import Foundation

/// 应用图标切换（Dock / Finder / 系统通知横幅）。
///
/// 系统通知横幅使用的图标来自 **App 包的 `.icns`**，无法只靠
/// `NSApp.applicationIconImage` 改变；因此切换时既要更新 Dock 图标，也要把所选的
/// `.icns` 写回 App 包并重新 ad-hoc 签名，之后重启 App 才会让 Finder / 通知图标生效。
final class AppIconController: ObservableObject {
    static let shared = AppIconController()

    /// 当前选择（同时持久化到 AppSettings）。
    @Published private(set) var style: AppIconStyle
    /// 是否已把 App 包内图标换成所选样式、等待重启生效。
    @Published private(set) var needsRestart = false
    /// 设置页展示的状态文案。
    @Published private(set) var message: String?

    private var installError: String?

    private static let targetIconName = "DSHStatus.icns"
    private static let brandResourceName = "DSHStatusBrand.icns"
    private static let whaleResourceName = "DSHStatusWhale.icns"

    private init() {
        style = AppSettings.shared.appIconStyle
        applyDockIcon()
    }

    // MARK: 对外操作

    /// App 启动时调用：把持久化的选择同步回 App 包（例如重装 DMG 后包内是默认图标）。
    func syncInstalledIconIfNeeded() {
        guard let desired = variantData(style), let current = currentBundleIconData(),
              current != desired else { return }
        if installBundleIcon(style, data: desired) {
            needsRestart = true
            message = "已按你的设置恢复「\(style.label)」图标；重启 App 后 Finder / 通知图标生效"
        }
    }

    func apply(_ newStyle: AppIconStyle) {
        style = newStyle
        AppSettings.shared.appIconStyle = newStyle
        applyDockIcon()
        if let data = variantData(newStyle), installBundleIcon(newStyle, data: data) {
            needsRestart = true
            message = "已切换为「\(newStyle.label)」；重启 App 后 Finder / 通知图标生效"
        } else {
            message = "Dock 图标已切换；但无法写入 App 包（\(installError ?? "权限不足")），Finder / 通知图标暂时无法更新"
        }
    }

    /// 重启 App（用于让 Finder / 通知图标生效）。
    func relaunch() {
        let path = Bundle.main.bundlePath
        let script = "sleep 1; /usr/bin/open -n \"\(path)\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// 调试/自检：App 包内图标是否已经是该样式。
    func bundleIconMatches(_ candidate: AppIconStyle) -> Bool {
        guard let desired = variantData(candidate), let current = currentBundleIconData() else { return false }
        return current == desired
    }

    // MARK: 内部

    private func applyDockIcon() {
        let image = style == .brand
            ? AppIconRenderer.image(size: 512)
            : AppIconRenderer.whaleImage(size: 512)
        NSApp.applicationIconImage = image
    }

    private func variantData(_ candidate: AppIconStyle) -> Data? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(
            candidate == .brand ? Self.brandResourceName : Self.whaleResourceName
        ) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func currentBundleIconData() -> Data? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(Self.targetIconName) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func installBundleIcon(_ candidate: AppIconStyle, data: Data) -> Bool {
        guard let target = Bundle.main.resourceURL?.appendingPathComponent(Self.targetIconName) else {
            installError = "缺少图标资源"
            return false
        }
        do {
            // 先写 .tmp 再原子替换，避免半写坏包。
            let tmp = target.deletingLastPathComponent()
                .appendingPathComponent(Self.targetIconName + ".tmp")
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
            resignBundle()
            touchBundle()
            return true
        } catch {
            installError = error.localizedDescription
            return false
        }
    }

    /// 修改包内资源会破坏原有签名；重新做 ad-hoc 签名，保证下次启动不报「已损坏」。
    private func resignBundle() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["--force", "--deep", "-s", "-", Bundle.main.bundlePath]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    private func touchBundle() {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: Bundle.main.bundlePath
        )
    }
}
