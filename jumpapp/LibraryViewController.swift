//
//  LibraryViewController.swift
//  jumpapp
//

import UIKit

final class LibraryViewController: UITableViewController {

    private var episodes: [EpisodeMeta] = []
    private var observer: UnsafeMutableRawPointer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "jumpapp"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64

        navigationItem.rightBarButtonItem = editButtonItem
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reloadLibrary), for: .valueChanged)

        reloadLibrary()
        registerForDownloads()
    }

    deinit {
        if let observer {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                observer,
                CFNotificationName(AppGroup.episodeDownloadedNotification as CFString),
                nil
            )
        }
    }

    private func registerForDownloads() {
        let name = AppGroup.episodeDownloadedNotification as CFString
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let controller = Unmanaged<LibraryViewController>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    controller.reloadLibrary()
                }
            },
            name,
            nil,
            .deliverImmediately
        )
        observer = Unmanaged.passUnretained(self).toOpaque()
    }

    @objc private func reloadLibrary() {
        episodes = EpisodeStore.loadLibrary()
        tableView.reloadData()
        refreshControl?.endRefreshing()

        if episodes.isEmpty {
            let label = UILabel()
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            label.font = .preferredFont(forTextStyle: .body)
            label.text = """
            ダウンロードした話がありません。

            Safari でとなりのヤングジャンプの話を開き、拡張機能から「アプリに送る」を押してください。
            """
            label.frame = tableView.bounds.insetBy(dx: 24, dy: 24)
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        episodes.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let episode = episodes[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = episode.title
        content.secondaryText = "\(episode.seriesTitle) · \(episode.pageCount)ページ"
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let episode = episodes[indexPath.row]
        let reader = ReaderViewController(episode: episode)
        navigationController?.pushViewController(reader, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete else { return }
        let episode = episodes[indexPath.row]
        try? EpisodeStore.delete(episodeID: episode.id)
        episodes.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        if episodes.isEmpty {
            reloadLibrary()
        }
    }
}
