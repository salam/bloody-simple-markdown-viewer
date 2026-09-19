import AppKit

// A programmatic entry point rather than NSApplicationMain: no nib to load,
// which is a measurable slice of launch time for an app whose whole point is
// opening instantly.
let application = NSApplication.shared
let controller = DocumentController()   // Must be the first NSDocumentController created.
let delegate = AppDelegate(documentController: controller)
application.delegate = delegate
application.setActivationPolicy(.regular)
application.mainMenu = MainMenu.build()
application.run()
