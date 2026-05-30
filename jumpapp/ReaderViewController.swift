//
//  ReaderViewController.swift
//  jumpapp
//

import UIKit

final class ReaderViewController: UIViewController {

    private let episode: EpisodeMeta
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    init(episode: EpisodeMeta) {
        self.episode = episode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = episode.title

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        loadPages()
    }

    private func loadPages() {
        activityIndicator.startAnimating()
        let pageURLs = EpisodeStore.pageURLs(for: episode.id)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let images: [UIImage] = pageURLs.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return UIImage(data: data)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.activityIndicator.stopAnimating()

                if images.isEmpty {
                    let label = UILabel()
                    label.text = "画像を読み込めませんでした"
                    label.textAlignment = .center
                    label.textColor = .secondaryLabel
                    self.view.addSubview(label)
                    label.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        label.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                        label.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
                    ])
                    return
                }

                for image in images {
                    let imageView = UIImageView(image: image)
                    imageView.contentMode = .scaleAspectFit
                    imageView.backgroundColor = .black
                    imageView.translatesAutoresizingMaskIntoConstraints = false
                    let aspect = image.size.height / max(image.size.width, 1)
                    imageView.heightAnchor.constraint(
                        equalTo: imageView.widthAnchor,
                        multiplier: aspect
                    ).isActive = true
                    self.stackView.addArrangedSubview(imageView)
                }
            }
        }
    }
}
