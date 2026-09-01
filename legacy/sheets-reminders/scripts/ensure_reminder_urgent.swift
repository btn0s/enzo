#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

enum UrgentError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let value): return value
        }
    }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String {
    attribute(element, name) as? String ?? ""
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func elements(from root: AXUIElement, limit: Int = 5_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var stack: [AXUIElement] = [root]
    var seen: [AXUIElement] = []

    while let current = stack.popLast(), result.count < limit {
        guard !seen.contains(where: { CFEqual($0, current) }) else { continue }
        seen.append(current)
        result.append(current)
        stack.append(contentsOf: children(current).reversed())
    }
    return result
}

func label(_ element: AXUIElement) -> String {
    [
        stringAttribute(element, kAXTitleAttribute),
        stringAttribute(element, kAXDescriptionAttribute),
        stringAttribute(element, kAXHelpAttribute),
    ].joined(separator: " ")
}

func press(_ element: AXUIElement) throws {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard result == .success else {
        throw UrgentError.message("Accessibility press failed: \(result.rawValue)")
    }
}

func reminderRow(in allElements: [AXUIElement], title: String) -> AXUIElement? {
    let prefix = "Incomplete, \(title),"
    return allElements.first {
        stringAttribute($0, kAXDescriptionAttribute).hasPrefix(prefix)
    }
}

func isUrgent(_ row: AXUIElement) -> Bool {
    stringAttribute(row, kAXDescriptionAttribute).contains(", Urgent,")
}

func markUrgentMenuItem(in allElements: [AXUIElement]) -> AXUIElement? {
    allElements.first {
        stringAttribute($0, kAXRoleAttribute) == kAXMenuItemRole
            && stringAttribute($0, kAXTitleAttribute) == "Mark as Urgent"
    }
}

func mainWindowMenuItem(in allElements: [AXUIElement]) -> AXUIElement? {
    allElements.first {
        stringAttribute($0, kAXRoleAttribute) == kAXMenuItemRole
            && stringAttribute($0, kAXTitleAttribute) == "Reminders"
    }
}

func parent(of element: AXUIElement) -> AXUIElement? {
    guard let value = attribute(element, kAXParentAttribute) else { return nil }
    return (value as! AXUIElement)
}

func selectReminder(startingAt element: AXUIElement) throws {
    var current: AXUIElement? = element
    for _ in 0..<6 {
        guard let candidate = current else { break }
        let result = AXUIElementSetAttributeValue(
            candidate,
            kAXSelectedAttribute as CFString,
            NSNumber(value: true)
        )
        if result == .success { return }
        current = parent(of: candidate)
    }
    throw UrgentError.message("Could not select the reminder row")
}

func waitUntil(
    deadline: Date,
    interval: TimeInterval = 0.15,
    _ operation: () throws -> Bool
) rethrows -> Bool {
    repeat {
        if try operation() { return true }
        Thread.sleep(forTimeInterval: interval)
    } while Date() < deadline
    return false
}

func ensureUrgent(title: String, timeout: TimeInterval) throws {
    guard AXIsProcessTrusted() else {
        throw UrgentError.message("Accessibility permission is required")
    }
    guard let app = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.reminders"
    ).first else {
        throw UrgentError.message("Reminders is not running")
    }
    if let bundleURL = app.bundleURL {
        _ = NSWorkspace.shared.open(bundleURL)
    }
    _ = app.activate()

    let root = AXUIElementCreateApplication(app.processIdentifier)
    let deadline = Date().addingTimeInterval(timeout)
    var invokedMenu = false
    var requestedWindow = false

    let succeeded = try waitUntil(deadline: deadline) {
        let allElements = elements(from: root)
        guard let row = reminderRow(in: allElements, title: title) else {
            if !requestedWindow, let menuItem = mainWindowMenuItem(in: allElements) {
                try press(menuItem)
                requestedWindow = true
            }
            return false
        }
        if isUrgent(row) {
            return true
        }

        if !invokedMenu, let menuItem = markUrgentMenuItem(in: allElements) {
            try selectReminder(startingAt: row)
            try press(menuItem)
            invokedMenu = true
        }
        return false
    }

    guard succeeded else {
        let allElements = elements(from: root)
        let rowFound = reminderRow(in: allElements, title: title) != nil
        let actionFound = markUrgentMenuItem(in: allElements) != nil
        throw UrgentError.message(
            "Could not verify Urgent in Reminders within \(Int(timeout)) seconds "
                + "(reminder row found: \(rowFound); Mark as Urgent found: \(actionFound))"
        )
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: ensure_reminder_urgent.swift REMINDER_TITLE\n", stderr)
    exit(2)
}

do {
    try ensureUrgent(title: CommandLine.arguments[1], timeout: 10)
    print("urgent")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
