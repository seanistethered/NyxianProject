/*
 Copyright (C) 2025 SeanIsTethered

 This file is part of Nyxian.

 FridaCodeManager is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 FridaCodeManager is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with FridaCodeManager. If not, see <https://www.gnu.org/licenses/>.
*/

import Foundation
import UIKit

//
// Replacement for OpenAppLoop which literally just attempted to open a app which didnt worked for already installed bundleids
//
// This one is way better it uses a Installation popup detection. on cancel it will be funny cause then you cannot do anything
// Will dig deeper
//
func OpenAppAfterReinstallTrampolineSwitch(_ installer: Installer,
                                           _ info: AppProject) -> Bool {
    
    ///
    /// Helper function to know if app is in focus
    ///
    func isAppInFocus() -> Bool {
        return DispatchQueue.main.sync {
            return UIApplication.shared.applicationState == .active
        }
    }
    
    ///
    /// Helper function to wait till a popup is gone
    ///
    func waitTillPopup() -> Bool {
        // wait till app goes to background
        var attempt: Int = 0
        let maxAttempt: Int = 10
        while isAppInFocus() {
            attempt += 1
            if attempt > maxAttempt {
                return false
            }
            
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // wait till app goes to foreground
        while !isAppInFocus() {
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        return true
    }
    
    ///
    /// We reset the shown progress of `XCButtonGlob`
    ///
    XCodeButton.resetProgress()
    
    ///
    /// Now we wait on the popup to go away the popup invoked by the system
    ///
    if !waitTillPopup() {
        ls_nsprint("[!] Popup appareance failure\n")
        return false
    }
    
    ///
    /// We need workspace
    ///
    guard let workspace = LSApplicationWorkspace.default() else {
        ls_nsprint("[!] Failed to get application workspace\n")
        return false
    }
    
    ///
    /// Installer checks
    ///
    let startTime = Date()
    while installer.status == .sendingManifest {
        if Date().timeIntervalSince(startTime) > 5.0 {
            return false
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    
    if installer.status == .sendingPayload {
        let semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
        installer.installCompletionHandler { semaphore.signal() }
        semaphore.wait()
    } else if !installer.completed {
        ls_nsprint("[!] Installer status doesnt add up\n")
        return false
    }
    
    ///
    /// Progress placeholder for the installation progress NSObject
    ///
    var progress: Progress?
    
    ///
    /// Now we wait till the progress is available
    ///
    var attempt: Int = 0
    let maxAttempts: Int = 10
    while progress == nil {
        progress = workspace.installProgress(forBundleID: installer.metadata.id, makeSynchronous: 0) as? Progress
        
        attempt += 1
        if attempt > maxAttempts {
            ls_nsprint("[!] Failed to get progress object from lsd\n")
            return false
        }
        
        Thread.sleep(forTimeInterval: 0.1)
    }
    
    func hookedCompletion() {
        workspace.clearCreatedProgress(forBundleID: installer.metadata.id)
    }
    
    ///
    /// Now we unwrap progress
    ///
    if let progress = progress {
        
        var oldProgress: Double = 0.0
        var oldDate: Date = Date()
        
        ///
        /// Now our loop
        ///
        while true {
            if oldProgress < progress.fractionCompleted {
                XCodeButton.updateProgressIncrement(progress: progress.fractionCompleted)
                oldProgress = progress.fractionCompleted
                oldDate = Date()
            } else {
                if oldDate.addingTimeInterval(20) < Date() {
                    workspace.clearCreatedProgress(forBundleID: installer.metadata.id)
                    ls_nsprint("[!] Progress seemed to have frozen\n")
                    return false
                }
            }
            
            if progress.isFinished {
                
                ///
                /// We attempt to open the application with the bundle identifier stored in `installed.metadata.id`
                ///
                while !workspace.openApplication(withBundleID: installer.metadata.id) {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                
                ///
                /// Nice, were done!
                ///
                workspace.clearCreatedProgress(forBundleID: installer.metadata.id)
                return true
            }
            
            Thread.sleep(forTimeInterval: 0.1)
        }
    } else {
        workspace.clearCreatedProgress(forBundleID: installer.metadata.id)
        return false
    }
}
