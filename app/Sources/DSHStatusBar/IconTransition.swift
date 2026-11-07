import AppKit

// MARK: - 图标状态切换：视觉状态 / 迁移计划
//
// 菜单栏图标由六个「视觉原子」拼成：鲸鱼、外环、内轨、彗星弧、中心数字、虚线环 + 短横。
// 状态切换不再靠「整张图瞬切」，而是对每个原子单独做过渡（见 docs/icon-transitions.md）：
//   · 内容（鲸鱼/内轨/虚线/数字之外的一切）：两帧图像交叉淡化
//   · 中心数字：旧数字上移淡出、新数字从下浮入（滚动/里程表）
//   · 外环：顺时针扫入（出现 / 换色底图保留旧环 paint-over）、逆时针收回（消失）
//   · 彗星弧：淡入淡出；内外环之间切换时半径连续变形
//   · 连接/断连：整块内容（含环）交叉淡化，彗星弧淡出

/// 图标当前的「视觉形态」。动画规划只看这个，不看底层 session 数组细节。
enum IconKind: Equatable {
    /// 未连接：灰色虚线环 + 短横。
    case disconnected
    /// 完全空闲：鲸鱼。
    case idle
    /// 只有待办（待回答/已停止/已完成）：彩色外环 + 中心数字。
    case attention
    /// 只有运行中：外环大小的轨道 + 彗星弧 + 中心数字。
    case running
    /// 运行中 + 待办：彩色外环 + 内层彗星弧（无数字）。
    case runningWithAttention
}

/// 图标的「视觉快照」：状态切换动画是否需要、以及做哪几个通道，都由它决定。
struct IconVisualState: Equatable {
    let kind: IconKind
    /// 外环颜色来源（红 > 黄 > 绿）；nil = 没有外环。
    let ringStatus: SessionStatus?
    /// 实际显示的中心数字。
    let number: Int?

    init(model: IconModel) {
        number = model.visibleCenterNumber
        guard model.connected else {
            kind = .disconnected
            ringStatus = nil
            return
        }
        let top = model.topPriorityStatus
        ringStatus = top
        if model.statuses.isEmpty {
            kind = .idle
        } else if top != nil && model.runningCount > 0 {
            kind = .runningWithAttention
        } else if top != nil {
            kind = .attention
        } else if model.runningCount > 0 {
            kind = .running
        } else {
            kind = .idle
        }
    }

    /// 内容通道（图像交叉淡化）需要区分的形态。数字/外环各自单独处理，不在此列。
    enum ContentKind: Equatable {
        case disconnected
        case whale
        /// 只有外环 + 数字：静态图里除数字外没有内容。
        case empty
        /// 外环大小的轨道（只有运行中）。
        case trackOuter
        /// 内层轨道（运行中 + 待办）。
        case trackInner
    }

    var contentKind: ContentKind {
        switch kind {
        case .disconnected: return .disconnected
        case .idle: return .whale
        case .attention: return .empty
        case .running: return .trackOuter
        case .runningWithAttention: return .trackInner
        }
    }

    var hasRing: Bool { ringStatus != nil }
}

/// 一次状态切换的「动画计划」：每个通道做什么，由 StatusItemController 在刷新时算出。
struct IconTransitionPlan {
    enum RingMode: Equatable {
        /// 外环没有变化（同色同有/同无），内容交叉淡化里直接带环。
        case none
        /// 无 → 有：顺时针扫入。
        case appear
        /// 有 → 无：逆时针收回。
        case disappear
        /// 颜色 A → B：保留旧环作底，新色顺时针 paint-over。
        case recolor
        /// 连接/断连：外环作为内容的一部分整块交叉淡化（彩色环 ↔ 虚线环）。
        case crossfade
    }

    enum CometMode: Equatable {
        case none
        /// 运行开始：彗星弧淡入并开始旋转。
        case appear
        /// 运行结束：彗星弧淡出后隐藏。
        case disappear
        /// 外环出现：彗星弧从外半径收进内半径。
        case moveInward
        /// 外环消失：彗星弧从内半径放回外半径。
        case moveOutward
    }

    struct NumberRoll: Equatable {
        let from: Int?
        let to: Int?
    }

    let ringMode: RingMode
    let oldRing: SessionStatus?
    let newRing: SessionStatus?
    let numberRoll: NumberRoll?
    let cometMode: CometMode
    let oldCometAnimated: Bool
    let newCometAnimated: Bool
    let includesRingInContent: Bool
    let includesNumberInContent: Bool
    /// 内容形态变化 → 需要图像交叉淡化（数字/外环不变时只有数字滚动，不需要）。
    let contentCrossfade: Bool

    /// 从旧模型到新模型是否需要播放过渡；nil = 视觉上没有变化。
    /// - Parameter oldCometAnimated / newCometAnimated：两端状态是否处于「彗星弧会动」模式
    ///   （运行中且运行动画开启、未降级）。它决定彗星是图层动画还是烘进静态图。
    static func plan(from oldModel: IconModel, to newModel: IconModel,
                     oldCometAnimated: Bool, newCometAnimated: Bool) -> IconTransitionPlan? {
        let old = IconVisualState(model: oldModel)
        let new = IconVisualState(model: newModel)
        guard old != new || oldCometAnimated != newCometAnimated else { return nil }

        let connectivityChanged = old.kind == .disconnected || new.kind == .disconnected

        let ringMode: RingMode
        if new.kind == .disconnected {
            // 断连：彩色环作为内容的一部分整块淡成虚线环（「颜色褪去」）。
            ringMode = .crossfade
        } else if old.kind == .disconnected {
            // 恢复连接：虚线环淡出；有外环则仍然从 12 点顺时针扫入（与外环出现保持同一语言）。
            ringMode = new.hasRing ? .appear : .none
        } else if old.hasRing && !new.hasRing {
            ringMode = .disappear
        } else if !old.hasRing && new.hasRing {
            ringMode = .appear
        } else if old.ringStatus != new.ringStatus {
            ringMode = .recolor
        } else {
            ringMode = .none
        }

        // 连接性变化时整块交叉淡化，数字不单独滚动（避免两套时间线打架）。
        let numberRoll: NumberRoll? = {
            guard !connectivityChanged, old.number != new.number else { return nil }
            return NumberRoll(from: old.number, to: new.number)
        }()

        var cometMode: CometMode = .none
        if oldCometAnimated && !newCometAnimated {
            cometMode = .disappear
        } else if !oldCometAnimated && newCometAnimated {
            cometMode = .appear
        } else if oldCometAnimated && newCometAnimated {
            let oldInner = old.kind == .runningWithAttention
            let newInner = new.kind == .runningWithAttention
            if oldInner != newInner {
                cometMode = newInner ? .moveInward : .moveOutward
            }
        }

        return IconTransitionPlan(
            ringMode: ringMode,
            oldRing: old.ringStatus,
            newRing: new.ringStatus,
            numberRoll: numberRoll,
            cometMode: cometMode,
            oldCometAnimated: oldCometAnimated,
            newCometAnimated: newCometAnimated,
            // 环单独做扫入/收回/换色时不能烘进内容图；其余情况内容图直接带环（两端一致，淡化不可见）。
            includesRingInContent: ringMode == .none || ringMode == .crossfade,
            includesNumberInContent: numberRoll == nil,
            contentCrossfade: old.contentKind != new.contentKind
                || (ringMode == .crossfade && old.hasRing != new.hasRing)
        )
    }
}

// MARK: - 动效参数（单一事实来源，文档 docs/icon-transitions.md 与实现保持一致）

enum IconMotion {
    /// 内容（鲸鱼 / 轨道 / 虚线环）交叉淡化。
    static let contentCrossfade: CFTimeInterval = 0.24
    /// 中心数字滚动：单侧时长 + 新数字延迟入场。
    static let numberRoll: CFTimeInterval = 0.18
    static let numberStagger: CFTimeInterval = 0.05
    /// 数字滚动的垂直位移（pt，22pt 画布内克制的里程表感）。
    static let numberSlide: CGFloat = 2.4
    /// 外环扫入 / 收回 / 换色。
    static let ringSweep: CFTimeInterval = 0.45
    /// 彗星弧淡入淡出。
    static let cometFade: CFTimeInterval = 0.18
    /// 彗星弧内半径 ⇄ 外半径变形（与外环扫入同拍）。
    static let cometMorph: CFTimeInterval = 0.45

    /// 一次过渡的总时长（所有通道同时起跑，取最长的那条）。
    static func duration(for plan: IconTransitionPlan) -> CFTimeInterval {
        var duration = contentCrossfade
        switch plan.ringMode {
        case .appear, .disappear, .recolor:
            duration = max(duration, ringSweep)
        case .none, .crossfade:
            break
        }
        switch plan.cometMode {
        case .appear, .disappear:
            duration = max(duration, cometFade)
        case .moveInward, .moveOutward:
            duration = max(duration, cometMorph)
        case .none:
            break
        }
        if plan.numberRoll != nil {
            duration = max(duration, numberRoll + numberStagger)
        }
        return duration
    }
}
