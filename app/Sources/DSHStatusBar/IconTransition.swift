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
    /// 实际显示的中心数字（按渲染文本归一化：>99 一律记 100，因为画面都是 `99+`）。
    /// 这样 100→101 这类「数值变了但渲染文本没变」的推送不会被误判成需要播放数字滚动。
    let number: Int?

    init(model: IconModel) {
        number = model.visibleCenterNumber.map { min($0, 100) }
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

        /// 数值变化方向：+1 增加（新值从下往上滚）、-1 减少（新值从上往下滚）、0 出现/消失（原地淡入淡出）。
        var direction: Int {
            guard let from, let to, from != to else { return 0 }
            return to > from ? 1 : -1
        }
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
    /// 「内容原子」（鲸鱼 / 轨道 / 未连接虚线环）是否变化。false = 两端内容完全相同，不需要交叉淡化。
    let contentAtomChanged: Bool
    /// 外环是否两端相同、可直接作为**公共原子**静态呈现（不参与任何通道的淡化/扫入）。
    let ringCommon: Bool
    /// 中心数字是否两端相同、可直接作为**公共原子**静态呈现（不参与滚动/淡化）。
    let numberCommon: Bool
    /// 连接性发生变化（断连 / 恢复）：数字与环作为「内容的一部分」整体淡化，不单独滚动。
    let connectivityChanged: Bool
    /// 外环通道自身的时长（默认 0.45s；同轨交接时压缩到 0.40–0.42s，给让位方腾时间）。
    let ringDuration: CFTimeInterval
    /// 各通道相对主拍起跑点的延迟（秒）：用于同轨交接（外环 ↔ 彗星）和「主通道先行、数字最后」的层次。
    let ringDelay: CFTimeInterval
    let cometDelay: CFTimeInterval
    let numberDelay: CFTimeInterval

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

        // 同轨交接：外环与彗星都在 r7.9 时不能同时「亮着换位」，让退场方先走，入场方等它让开。
        // 半径迁移（running ↔ both）让环先立/先退 0.08s，读起来是「外框先动、活动弧随后换道」。
        var cometDelay: CFTimeInterval = 0
        var ringDelay: CFTimeInterval = 0
        var ringDuration = IconMotion.ringSweep
        switch (ringMode, cometMode) {
        case (.disappear, .appear):
            // 待办 → 运行中：红/黄/绿环先收回（压缩到 0.40s），彗星 0.30s 后再淡入。
            ringDuration = IconMotion.ringYieldDuration
            cometDelay = IconMotion.ringYieldCometDelay
        case (.appear, .disappear):
            // 运行中 → 待办：彗星先淡出（0.18s），外环 0.18s 后扫入（压缩到 0.42s）。
            ringDuration = IconMotion.ringTakeoverDuration
            ringDelay = IconMotion.cometFade
        case (_, .moveInward), (_, .moveOutward):
            cometDelay = IconMotion.laneChangeLead
        case (.appear, .appear):
            cometDelay = IconMotion.laneChangeLead
        default:
            break
        }
        // 数字是「结果」：有外环/彗星/内容等主通道在动时，晚于主通道起跑 0.10s 入场；
        // 若外环本身被推迟（同轨交接时先让彗星退场），数字还要再等外环起跑，避免「数字先于环」。
        // 纯数字变化（3→2）没有主通道，立即开始。
        let primaryChannelActive = ringMode != .none || cometMode != .none
        var numberDelay: CFTimeInterval = 0
        if primaryChannelActive {
            numberDelay = max(IconMotion.numberHierarchyDelay,
                              ringMode != .none ? ringDelay + IconMotion.numberHierarchyDelay : 0)
        }

        // 所有通道都无事可做 = 视觉上没有变化（典型：>99 时 100→101 渲染文本都是「99+」）。
        // 直接返回 nil：不建临时层、不播过渡，也不改变显示状态。
        let contentAtomChanged = old.contentKind != new.contentKind
        if ringMode == .none, cometMode == .none, numberRoll == nil, !contentAtomChanged {
            return nil
        }

        return IconTransitionPlan(
            ringMode: ringMode,
            oldRing: old.ringStatus,
            newRing: new.ringStatus,
            numberRoll: numberRoll,
            cometMode: cometMode,
            oldCometAnimated: oldCometAnimated,
            newCometAnimated: newCometAnimated,
            // 环单独做扫入/收回/换色时不能烘进内容图；其余情况内容图直接带环（两端一致 → 走公共原子层）。
            includesRingInContent: ringMode == .none || ringMode == .crossfade,
            includesNumberInContent: numberRoll == nil,
            contentAtomChanged: contentAtomChanged,
            // 两端同色的环不需要任何环通道动画 → 作为公共原子静态呈现（避免双图淡化把它压到 75% 亮度）。
            ringCommon: ringMode == .none && old.hasRing && new.hasRing,
            // 数字不滚动且不随连接性整体淡化 → 公共原子。
            numberCommon: numberRoll == nil && !connectivityChanged,
            connectivityChanged: connectivityChanged,
            ringDuration: ringDuration,
            ringDelay: ringDelay,
            cometDelay: cometDelay,
            numberDelay: numberDelay
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
    /// 「环让位」变体：待办 → 运行中时外环收回压缩到 0.40s。
    static let ringYieldDuration: CFTimeInterval = 0.40
    /// 「环接管」变体：运行中 → 待办时外环扫入压缩到 0.42s（前置 0.18s 等彗星退场）。
    static let ringTakeoverDuration: CFTimeInterval = 0.42
    /// 环让位后彗星入场延迟：环 0.40s 收回期间，彗星等到 0.30s 才开始淡入（仅 0.10s 交叠）。
    static let ringYieldCometDelay: CFTimeInterval = 0.30
    /// 半径迁移/环先立时，彗星弧稍晚起跑，避免和外环抢第一眼。
    static let laneChangeLead: CFTimeInterval = 0.08
    /// 有主通道动画时，中心数字（结果）晚这么多久入场。
    static let numberHierarchyDelay: CFTimeInterval = 0.10

    /// 一次过渡的总时长：每条通道 = 延迟 + 自身时长，取最长的一条（≤ 0.60s）。
    static func duration(for plan: IconTransitionPlan) -> CFTimeInterval {
        var duration = contentCrossfade
        switch plan.ringMode {
        case .appear, .disappear, .recolor:
            duration = max(duration, plan.ringDelay + plan.ringDuration)
        case .none, .crossfade:
            break
        }
        switch plan.cometMode {
        case .appear, .disappear:
            duration = max(duration, plan.cometDelay + cometFade)
        case .moveInward, .moveOutward:
            duration = max(duration, plan.cometDelay + cometMorph)
        case .none:
            break
        }
        if plan.numberRoll != nil {
            duration = max(duration, plan.numberDelay + numberRoll + numberStagger)
        }
        return min(duration, 0.60)
    }
}
