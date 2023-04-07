//
//  main.swift
//  OpenAIBar
//
//  Created by Andrew Duffy on 3/28/23.
//

import Foundation
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

