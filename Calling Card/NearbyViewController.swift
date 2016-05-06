//
//  NearbyViewController.swift
//  Calling Card
//
//  Created by Stuart Kent on 4/26/16.
//  Copyright © 2016 Stuart Kent. All rights reserved.
//

import UIKit

final class NearbyViewController: UIViewController {
    
    static let storyboardId = "NearbyViewController"
    
    private let savedUsersManager = SavedUsersManager()

    private var currentUser: User?
    
    private var nearbyUsers: [User] = [] {
        didSet {
            tableView.reloadData()
        }
    }
    
    private var gnsPermissionProxy: GNSPermission?
    
    private var currentPublicationReference: GNSPublication? {
        didSet {
            tableView.reloadData()
        }
    }
    
    private var currentSubscriptionReference: GNSSubscription? {
        didSet {
            tableView.reloadData()
        }
    }
    
    private lazy var messageManager: GNSMessageManager = {
        GNSMessageManager(APIKey: "AIzaSyClHL5KdqrIeyHjfWxRtb8C0nYmwffLGtI") { params in
            params.microphonePermissionErrorHandler = { hasError in
                if hasError {
                    // todo: do we get callback each time this status changes; or only initially?
                }
            }
            
            params.bluetoothPermissionErrorHandler = { hasError in
                if hasError {
                    
                }
            }
            
            params.bluetoothPowerErrorHandler = { hasError in
                if hasError {
                    
                }
            }
        }
    }()
    
    private var messageToPublish: GNSMessage? {
        if let currentUser = currentUser,
            currentUserJSON = currentUser.toNSData() {
            
                return GNSMessage(content: currentUserJSON)
        }
        
        return nil
    }
    
    private var activelyPublishing: Bool {
        return GNSPermission.isGranted() && currentPublicationReference != nil
    }
    
    private var activelySubscribing: Bool {
        return GNSPermission.isGranted() && currentSubscriptionReference != nil
    }

    @IBOutlet private weak var tableView: UITableView!

    @IBAction func signOutButtonTapped(sender: UIBarButtonItem) {
        cancelAllNearbyActivity()
        clearUser()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        GNSPermission.setGranted(false)
        
        configureTableView()
        
        gnsPermissionProxy = GNSPermission { [weak self] granted in
            if !granted {
                self?.cancelAllNearbyActivity()
            }
            
            self?.tableView.reloadData()
        }
    }
    
    private func configureTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 44
        tableView.rowHeight = UITableViewAutomaticDimension
    }
    
    private func attemptToPublish() {
        if let messageToPublish = messageToPublish {
            currentPublicationReference = messageManager.publicationWithMessage(messageToPublish)
        }
    }
    
    private func attemptToSubscribe() {
        currentSubscriptionReference = messageManager.subscriptionWithMessageFoundHandler(
            { [weak self] foundMessage in
                if let _self = self,
                    nearbyUser = User(nsData: foundMessage.content)
                    where !_self.nearbyUsers.map({ user in return user.id }).contains(nearbyUser.id) {
                    
                        _self.nearbyUsers = [nearbyUser] + _self.nearbyUsers
                }
            },
            messageLostHandler: { [weak self] lostMessage in
                if let _self = self,
                    lostUser = User(nsData: lostMessage.content) {
                    
                        _self.nearbyUsers = _self.nearbyUsers.filter { user in return user.id != lostUser.id }
                }
            })
    }
    
    private func stopPublishing() {
        currentPublicationReference = nil
    }
    
    private func stopSubscribing() {
        currentSubscriptionReference = nil
    }
    
    private func cancelAllNearbyActivity() {
        stopPublishing()
        stopSubscribing()
    }
    
    private func clearUser() {
        GIDSignIn.sharedInstance().signOut()
        GIDSignIn.sharedInstance().disconnect()
    }
    
}

extension NearbyViewController: CurrentUserRecipient {
    
    func setCurrentUser(currentUser: User) {
        self.currentUser = currentUser
    }
    
}

extension NearbyViewController: UITableViewDataSource {
    
    private static let STATIC_CELL_COUNT = 3
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return NearbyViewController.STATIC_CELL_COUNT + nearbyUsers.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        switch indexPath.row {
        case 0:
            let result = tableView.dequeueReusableCellWithIdentifier(
                OperationControlTableViewCell.reuseIdentifier) as? OperationControlTableViewCell
            
            result?.operation = .Publish
            result?.controlOn = activelyPublishing
            result?.controlDelegate = self
            
            return result ?? UITableViewCell()
        case 1:
            let result = tableView.dequeueReusableCellWithIdentifier(
                UserTableViewCell.reuseIdentifier) as? UserTableViewCell
            
            result?.bindUser(currentUser!)
            result?.setBorderColor(activelyPublishing ? .Green : .Red)
            
            return result ?? UITableViewCell()
        case 2:
            let result = tableView.dequeueReusableCellWithIdentifier(
                OperationControlTableViewCell.reuseIdentifier) as? OperationControlTableViewCell
        
            result?.operation = .Subscribe
            result?.controlOn = activelySubscribing
            result?.controlDelegate = self
            
            return result ?? UITableViewCell()
        default:
            let result = tableView.dequeueReusableCellWithIdentifier(
                UserTableViewCell.reuseIdentifier) as? UserTableViewCell
            
            result?.bindUser(nearbyUsers[indexPath.row - NearbyViewController.STATIC_CELL_COUNT])
            
            return result ?? UITableViewCell()
        }
    }

}

extension NearbyViewController: UITableViewDelegate {
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let row = indexPath.row
        
        if (row >= NearbyViewController.STATIC_CELL_COUNT) {
            let tappedUser = nearbyUsers[row - NearbyViewController.STATIC_CELL_COUNT]

            let savePrompt = UIAlertController()
            savePrompt.message = "Save \(tappedUser.name)'s info?"
            savePrompt.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))
            savePrompt.addAction(UIAlertAction(title: "Save", style: .Default) { _ in
                self.savedUsersManager.saveUser(tappedUser)
                self.tableView.reloadData()
            })
        }
    }
    
}

extension NearbyViewController: OperationControlTableViewCellDelegate {
    
    func controlToggled(operation: NearbyAPIOperation) {
        switch operation {
        case .Publish:
            if activelyPublishing {
                stopPublishing()
            } else {
                attemptToPublish()
            }
        case .Subscribe:
            if activelySubscribing {
                stopSubscribing()
            } else {
                attemptToSubscribe()
            }
        }
    }
    
}
