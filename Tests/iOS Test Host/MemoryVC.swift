//
//  MemoryVC.swift
//  WireSyncEngine
//
//  Created by Marco Conti on 16.08.17.
//  Copyright © 2017 Zeta Project Gmbh. All rights reserved.
//

import UIKit
import WireSyncEngine
import avs

@objc public class MemoryVC: UIViewController {

    var session: SessionManager!
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        self.session = SessionManager(
            appVersion: "0.0.0",
            mediaManager: AVSMediaManager.default(),
            analytics: nil,
            delegate: nil,
            application: UIApplication.shared,
            launchOptions: [:],
            blacklistDownloadInterval : 40000
        )
        
        let button = UIButton(frame: self.view.bounds)
        button.setTitle("Boon", for: .normal)
        self.view.addSubview(button)
        button.addTarget(self, action: #selector(boom(_:)), for: .touchUpInside)
    }

    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    public func boom(_ sender: Any?) {
        self.session = nil
        print("Boom")
    }
    
}
