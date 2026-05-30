//
//  SceneDelegate.swift
//  jumpapp
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let library = LibraryViewController(style: .insetGrouped)
        window.rootViewController = UINavigationController(rootViewController: library)
        window.makeKeyAndVisible()
        self.window = window
    }
}
