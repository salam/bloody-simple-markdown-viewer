import AppKit

/// The main menu, built in code. There is no nib to load, which keeps launch
/// lean for an app whose entire premise is opening instantly.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(applicationMenu())
        main.addItem(fileMenu())
        main.addItem(editMenu())
        main.addItem(viewMenu())
        main.addItem(windowMenu())
        main.addItem(helpMenu())
        return main
    }

    private static func submenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        build(menu)
        item.submenu = menu
        return item
    }

    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?,
                            _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command,
                            target: AnyObject? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        if let target { item.target = target }
        menu.addItem(item)
    }

    private static func applicationMenu() -> NSMenuItem {
        submenu("Markdown") { menu in
            add(menu, "About A Bloody Simple Markdown Viewer",
                #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
            menu.addItem(.separator())
            add(menu, "Make Default Markdown App",
                #selector(AppCommands.makeDefaultMarkdownApp(_:)))
            menu.addItem(.separator())

            let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
            let servicesMenu = NSMenu()
            services.submenu = servicesMenu
            NSApp.servicesMenu = servicesMenu
            menu.addItem(services)
            menu.addItem(.separator())

            add(menu, "Hide Markdown", #selector(NSApplication.hide(_:)), "h")
            add(menu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
                [.command, .option])
            add(menu, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
            menu.addItem(.separator())
            add(menu, "Quit Markdown", #selector(NSApplication.terminate(_:)), "q")
        }
    }

    private static func fileMenu() -> NSMenuItem {
        submenu("File") { menu in
            add(menu, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")

            // NSDocumentController adopts this menu only when it carries the
            // standard identifier. Without it the framework inserts a second
            // Open Recent menu of its own, and one of the two stays empty.
            let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
            let recentMenu = NSMenu(title: "Open Recent")
            recentMenu.identifier = NSUserInterfaceItemIdentifier("NSRecentDocumentsMenu")
            add(recentMenu, "Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))
            recent.submenu = recentMenu
            menu.addItem(recent)

            menu.addItem(.separator())
            add(menu, "Close", #selector(NSWindow.performClose(_:)), "w")
            add(menu, "Save", #selector(NSDocument.save(_:)), "s")
            add(menu, "Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
            add(menu, "Revert to Saved", #selector(NSDocument.revertToSaved(_:)))
            menu.addItem(.separator())
            add(menu, "Export as PDF…", #selector(AppCommands.exportAsPDF(_:)), "e",
                [.command, .shift])
            menu.addItem(.separator())
            add(menu, "Page Setup…", #selector(NSApplication.runPageLayout(_:)), "p",
                [.command, .shift])
            add(menu, "Print…", #selector(NSView.printView(_:)), "p")
        }
    }

    private static func editMenu() -> NSMenuItem {
        submenu("Edit") { menu in
            add(menu, "Undo", Selector(("undo:")), "z")
            add(menu, "Redo", Selector(("redo:")), "z", [.command, .shift])
            menu.addItem(.separator())
            add(menu, "Cut", #selector(NSText.cut(_:)), "x")
            add(menu, "Copy", #selector(NSText.copy(_:)), "c")
            add(menu, "Paste", #selector(NSText.paste(_:)), "v")
            add(menu, "Select All", #selector(NSText.selectAll(_:)), "a")
            menu.addItem(.separator())
            add(menu, "Find…", #selector(AppCommands.showFind(_:)), "f")
            add(menu, "Find Next", #selector(AppCommands.findNext(_:)), "g")
            add(menu, "Find Previous", #selector(AppCommands.findPrevious(_:)), "g", [.command, .shift])
        }
    }

    private static func viewMenu() -> NSMenuItem {
        submenu("View") { menu in
            add(menu, "Show Markdown Source", #selector(AppCommands.toggleSourceMode(_:)), "e",
                [.command, .shift])
            menu.addItem(.separator())
            add(menu, "Show Outline", #selector(AppCommands.toggleOutline(_:)), "0", [.command, .option])
            menu.addItem(.separator())
            add(menu, "Add Bookmark", #selector(AppCommands.addBookmark(_:)), "d")
            menu.addItem(.separator())
            add(menu, "Show Everything", #selector(AppCommands.clearTaskFilter(_:)), "0",
                [.command, .shift])
            menu.addItem(.separator())
            add(menu, "Actual Size", #selector(AppCommands.resetZoom(_:)), "0")
            add(menu, "Zoom In", #selector(AppCommands.zoomIn(_:)), "+")
            add(menu, "Zoom Out", #selector(AppCommands.zoomOut(_:)), "-")
            menu.addItem(.separator())
            add(menu, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f",
                [.command, .control])
        }
    }

    private static func windowMenu() -> NSMenuItem {
        let item = submenu("Window") { menu in
            add(menu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
            add(menu, "Zoom", #selector(NSWindow.performZoom(_:)))
            menu.addItem(.separator())
            add(menu, "Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "\u{F702}",
                [.command, .option])
            add(menu, "Show Next Tab", #selector(NSWindow.selectNextTab(_:)), "\u{F703}",
                [.command, .option])
            add(menu, "Move Tab to New Window", #selector(NSWindow.moveTabToNewWindow(_:)))
            add(menu, "Merge All Windows", #selector(NSWindow.mergeAllWindows(_:)))
            menu.addItem(.separator())
            add(menu, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        }
        NSApp.windowsMenu = item.submenu
        return item
    }

    private static func helpMenu() -> NSMenuItem {
        let item = submenu("Help") { menu in
            add(menu, "Markdown Syntax Guide", #selector(AppCommands.showSyntaxGuide(_:)), "?")
            add(menu, "Project on GitHub", #selector(AppCommands.openProjectPage(_:)))
        }
        NSApp.helpMenu = item.submenu
        return item
    }
}

/// Marker protocol carrying the selectors the menu sends down the responder
/// chain. Declaring them in one place keeps the menu and the handlers honest.
@objc protocol AppCommands {
    func toggleSourceMode(_ sender: Any?)
    func toggleOutline(_ sender: Any?)
    func showFind(_ sender: Any?)
    func findNext(_ sender: Any?)
    func findPrevious(_ sender: Any?)
    func zoomIn(_ sender: Any?)
    func zoomOut(_ sender: Any?)
    func resetZoom(_ sender: Any?)
    func addBookmark(_ sender: Any?)
    func exportAsPDF(_ sender: Any?)
    func clearTaskFilter(_ sender: Any?)
    func makeDefaultMarkdownApp(_ sender: Any?)
    func showSyntaxGuide(_ sender: Any?)
    func openProjectPage(_ sender: Any?)
}
