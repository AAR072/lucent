import SwiftUI
import UIKit

struct PhotoGalleryView: View {
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID
    let onClose: () -> Void

    init(model: CameraModel, selectedID: UUID, onClose: @escaping () -> Void) {
        self.model = model
        _selectedID = State(initialValue: selectedID)
        self.onClose = onClose
    }

    var body: some View {
        PhotoPages(records: model.records, selectedID: $selectedID,
                   onSave: { model.reloadLibrary() }, onBack: { dismiss() },
                   onClose: onClose, onRemove: { id in
            let index = model.records.firstIndex { $0.id == id } ?? 0
            model.reloadLibrary()
            if model.records.isEmpty { dismiss() }
            else { selectedID = model.records[min(index, model.records.count - 1)].id }
        })
        .ignoresSafeArea(.container).statusBarHidden(true).persistentSystemOverlays(.hidden)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// UIKit paging supplies interactive transitions while keeping RAW decodes bounded
/// to the visible photograph and its immediate neighbors.
private struct PhotoPages: UIViewControllerRepresentable {
    var records: [CaptureRecord]
    @Binding var selectedID: UUID
    var onSave: () -> Void
    var onBack: () -> Void
    var onClose: () -> Void
    var onRemove: (UUID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        controller.view.backgroundColor = .black
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        context.coordinator.controller = controller
        context.coordinator.update(self)
        return controller
    }
    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.update(self)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PhotoPages
        weak var controller: UIPageViewController?
        private var pages: [UUID: UIHostingController<PhotoLabView>] = [:]
        private var pagingAllowed: [UUID: Bool] = [:]
        private var transitioning = false
        init(_ parent: PhotoPages) { self.parent = parent }

        func update(_ parent: PhotoPages) {
            self.parent = parent
            guard let controller, !transitioning, parent.records.contains(where: { $0.id == parent.selectedID }) else { return }
            if id(of: controller.viewControllers?.first) != parent.selectedID,
               let page = page(for: parent.selectedID) {
                controller.setViewControllers([page], direction: .forward, animated: false)
            }
            prunePages()
            for (id, page) in pages {
                if let index = parent.records.firstIndex(where: { $0.id == id }) {
                    page.rootView = photoView(record: parent.records[index], index: index)
                }
            }
            updatePaging()
        }

        private func id(of page: UIViewController?) -> UUID? {
            pages.first { $0.value === page }?.key
        }
        private func page(for id: UUID) -> UIViewController? {
            if let cached = pages[id] { return cached }
            guard let index = parent.records.firstIndex(where: { $0.id == id }) else { return nil }
            let page = UIHostingController(rootView: photoView(record: parent.records[index], index: index))
            page.view.backgroundColor = .black
            pages[id] = page
            return page
        }
        private func photoView(record: CaptureRecord, index: Int) -> PhotoLabView {
            let id = record.id
            return PhotoLabView(
                record: record, onSave: { [weak self] in self?.parent.onSave() },
                onClose: { [weak self] in self?.parent.onClose() },
                onBack: { [weak self] in self?.parent.onBack() },
                onRemove: { [weak self] in self?.parent.onRemove(id) },
                onPagingChanged: { [weak self] allowed in
                    self?.pagingAllowed[id] = allowed
                    self?.updatePaging()
                }, position: "Photograph \(index + 1) of \(parent.records.count)")
        }
        private func neighbor(of page: UIViewController, offset: Int) -> UIViewController? {
            guard let id = id(of: page), let index = parent.records.firstIndex(where: { $0.id == id }) else { return nil }
            let next = index + offset
            guard parent.records.indices.contains(next) else { return nil }
            return self.page(for: parent.records[next].id)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            neighbor(of: viewController, offset: -1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            neighbor(of: viewController, offset: 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            transitioning = true
        }
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            transitioning = false
            if completed, let id = id(of: pageViewController.viewControllers?.first) { parent.selectedID = id }
            prunePages()
            updatePaging()
        }
        private func updatePaging() {
            guard let controller, let id = id(of: controller.viewControllers?.first) else { return }
            // This is the page controller's own scroll view, not the photograph's.
            controller.view.subviews.compactMap { $0 as? UIScrollView }.first?.isScrollEnabled = pagingAllowed[id] ?? true
        }
        private func prunePages() {
            guard let index = parent.records.firstIndex(where: { $0.id == parent.selectedID }) else { return }
            let retained = Set(parent.records[max(0, index - 1)...min(parent.records.count - 1, index + 1)].map(\.id))
            pages = pages.filter { retained.contains($0.key) }
            pagingAllowed = pagingAllowed.filter { retained.contains($0.key) }
        }
    }
}
