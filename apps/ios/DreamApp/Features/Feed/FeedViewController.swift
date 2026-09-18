import SwiftUI
import UIKit

/// The Feed tab: full-screen cards paged vertically. UIKit owns the list,
/// paging, prefetching, and the lookup drawer; SwiftUI draws each card and
/// the floating header. The model is read in `updateProperties()`, so any
/// change it publishes lands in the next update pass.
final class FeedViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    private let model: FeedModel
    private let pronunciation: Pronunciation
    private let mediaCache: MediaCache
    private let onBack: () -> Void
    private let layoutMetrics = FeedLayoutMetrics()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Int>!
    private var header: UIHostingController<FeedHeaderView>!
    private var stateHost: UIHostingController<FeedStateView>?
    private var lookupController: WordLookupController?
    private var presentedLookupID: UUID?
    private var appliedEntryIDs: [Int] = []
    private var presentedError: String?

    init(database: AppDatabase, settings: AppSettingsModel, pronunciation: Pronunciation,
         mediaCache: MediaCache, onBack: @escaping () -> Void) {
        model = FeedModel(
            repository: FeedRepository(writer: database.writer),
            settings: settings,
            pronunciation: pronunciation
        )
        self.pronunciation = pronunciation
        self.mediaCache = mediaCache
        self.onBack = onBack
        super.init(nibName: nil, bundle: nil)
        model.onAdvance = { [weak self] index in self?.scroll(to: index) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(FeedColors.background)

        let layout = UICollectionViewCompositionalLayout { _, _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1))
            let item = NSCollectionLayoutItem(layoutSize: size)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
            return NSCollectionLayoutSection(group: group)
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.backgroundColor = UIColor(FeedColors.background)
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        view.addSubview(collectionView)

        let registration = UICollectionView.CellRegistration<UICollectionViewCell, FeedEntry> {
            [unowned self] cell, _, entry in
            cell.contentConfiguration = UIHostingConfiguration {
                FeedCardView(
                    entry: entry,
                    model: model,
                    layout: layoutMetrics,
                    pronunciation: pronunciation,
                    mediaCache: mediaCache
                )
            }
            .margins(.all, 0)
            .background(FeedColors.background)
        }
        dataSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) {
            [unowned self] collectionView, indexPath, serial in
            guard let entry = model.entry(id: serial) else { return UICollectionViewCell() }
            return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: entry)
        }

        header = UIHostingController(rootView: FeedHeaderView(model: model, onBack: onBack))
        header.view.backgroundColor = .clear
        addChild(header)
        view.addSubview(header.view)
        header.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            header.view.heightAnchor.constraint(equalToConstant: 44),
        ])
        header.didMove(toParent: self)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let insets = view.safeAreaInsets
        layoutMetrics.safeAreaInsets = EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model.setVisible(true)
        setNeedsUpdateProperties()
    }

    // Fires on a root tab switch: the container forwards appearance callbacks.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.setVisible(false)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Observation

    override func updateProperties() {
        super.updateProperties()
        model.syncSettings()
        applyEntries()
        updateStateView()
        updateLookup()
        updateErrorAlert()
        // Hands-free reading keeps the screen awake.
        UIApplication.shared.isIdleTimerDisabled = model.isAutoAdvancing && viewIfLoaded?.window != nil
    }

    private func applyEntries() {
        let ids = model.entries.map(\.id)
        guard ids != appliedEntryIDs else { return }
        let restarted = ids.first != appliedEntryIDs.first
        appliedEntryIDs = ids
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        dataSource.apply(snapshot, animatingDifferences: false)
        if restarted {
            collectionView.setContentOffset(.zero, animated: false)
        }
    }

    private func updateStateView() {
        let state: FeedStateView.State?
        if model.entries.isEmpty {
            switch model.status {
            case .loading: state = nil
            case .ready: state = .empty
            case .failed: state = .failed
            }
        } else {
            state = nil
        }
        guard let state else {
            stateHost?.willMove(toParent: nil)
            stateHost?.view.removeFromSuperview()
            stateHost?.removeFromParent()
            stateHost = nil
            return
        }
        let root = FeedStateView(state: state) { [weak self] in self?.model.retry() }
        if let stateHost {
            stateHost.rootView = root
            return
        }
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        view.insertSubview(host.view, belowSubview: header.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        stateHost = host
    }

    private func updateErrorAlert() {
        guard let message = model.saveError, message != presentedError, presentedViewController == nil else { return }
        presentedError = message
        let alert = UIAlertController(
            title: String(localized: "errorTitle", table: "Feed"), message: message, preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "ok", table: "Feed"), style: .default) { [weak self] _ in
            self?.presentedError = nil
            self?.model.saveError = nil
        })
        present(alert, animated: true)
    }

    // MARK: - Lookup drawer

    private func updateLookup() {
        guard let lookup = model.lookup else {
            if let lookupController, !lookupController.isBeingDismissed {
                lookupController.dismiss(animated: true)
            }
            return
        }
        guard presentedLookupID != lookup.id, lookupController == nil, presentedViewController == nil,
              let context = model.context, let window = view.window,
              let indexPath = dataSource.indexPath(for: lookup.entryID),
              let cell = collectionView.cellForItem(at: indexPath)
        else { return }
        let rowBottom = cell.contentView.convert(CGPoint(x: 0, y: lookup.rowBottom), to: window).y
        let controller = WordLookupController(
            chunk: lookup.chunk,
            context: context,
            pronunciation: pronunciation,
            anchorTop: rowBottom + FeedMetrics.lookupTopGap
        ) { [weak self] in
            guard let self else { return }
            lookupController = nil
            presentedLookupID = nil
            model.closeLookup(lookup.id)
        }
        lookupController = controller
        presentedLookupID = lookup.id
        controller.prepareForPresentation(in: window)
        present(controller, animated: true)
    }

    // MARK: - Paging

    private func scroll(to index: Int) {
        guard model.entries.indices.contains(index) else { return }
        collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .top, animated: true)
    }

    /// The card under the settled offset becomes active.
    private func settle() {
        let height = collectionView.bounds.height
        guard height > 0 else { return }
        model.cardBecameActive(Int((collectionView.contentOffset.y / height).rounded()))
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A swipe that snaps back to the same card must not keep reading it.
        model.interrupt()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settle()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        settle()
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard model.entries.indices.contains(indexPath.item),
                  let photo = model.entries[indexPath.item].card.photo else { continue }
            // The cache keeps the download even if nobody waits for it.
            Task { _ = try? await mediaCache.file(for: photo.storagePath) }
        }
    }
}

// MARK: - Header

/// The floating controls over the hero: back to the dictionary, mute, and
/// hands-free reading.
private struct FeedHeaderView: View {
    let model: FeedModel
    let onBack: () -> Void

    var body: some View {
        HStack {
            HeaderCircleButton(symbol: "chevron.left", action: onBack)
                .accessibilityLabel(Text("back", tableName: "Feed"))
            Spacer()
            HStack(spacing: 8) {
                HeaderCircleButton(
                    symbol: model.isAutoplaying ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    action: model.toggleAutoplay
                )
                .accessibilityLabel(Text(model.isAutoplaying ? "mute" : "unmute", tableName: "Feed"))
                HeaderCircleButton(
                    symbol: model.isAutoAdvancing ? "pause.fill" : "play.fill",
                    tint: model.isAutoAdvancing ? FeedColors.accent : .white,
                    action: model.toggleAutoAdvance
                )
                .accessibilityLabel(Text("autoAdvance", tableName: "Feed"))
            }
        }
    }
}

/// A 44-point translucent circle over the photo, as the old pseudo-glass
/// header buttons were.
private struct HeaderCircleButton: View {
    let symbol: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: .circle)
                .background(FeedColors.heroControl, in: .circle)
                .overlay { Circle().strokeBorder(FeedColors.controlBorder, lineWidth: 1) }
                .contentShape(.circle)
        }
        .buttonStyle(.pressedOpacity)
    }
}

// MARK: - Screen states

/// What the screen shows without cards: nothing to review, or a failure
/// with a retry.
private struct FeedStateView: View {
    enum State {
        case empty
        case failed
    }

    let state: State
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            switch state {
            case .empty:
                Text("empty.title", tableName: "Feed")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text("empty.subtitle", tableName: "Feed")
                    .font(.system(size: 16))
                    .foregroundStyle(FeedColors.textSecondary)
            case .failed:
                Text("error.load", tableName: "Feed")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Button(action: retry) {
                    Text("retry", tableName: "Feed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FeedColors.accent)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(FeedColors.accentSoft, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.pressedOpacity)
                .padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FeedColors.background)
    }
}
