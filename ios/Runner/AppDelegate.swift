import Contacts
import ContactsUI
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var contactPicker: ContactPickerChannel?
  private var backup: BackupChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The one piece of native code in the app: the system contact picker.
    // See lib/data/contact_picker.dart for why no package is used.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ImpairGencyContacts") {
      contactPicker = ContactPickerChannel(messenger: registrar.messenger())
    }
    // Keeps saved friends' faces out of iCloud and computer backups. See
    // lib/data/friend_store_io.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ImpairGencyBackup") {
      backup = BackupChannel(messenger: registrar.messenger())
    }
  }
}

/// Marks a folder as not to be backed up. Application Support is backed up by
/// default on iOS; the faces folder in it must not be.
final class BackupChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "ph.impairgency/backup", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup",
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path, isDirectory: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "backup", message: error.localizedDescription, details: nil))
      }
    }
  }
}

/// CNContactPickerViewController hands back the one contact the user chose.
/// It needs no contacts permission, because the app never reads the address
/// book - the user reads it and hands over one number.
final class ContactPickerChannel: NSObject, CNContactPickerDelegate {
  private let channel: FlutterMethodChannel
  private var pending: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "ph.impairgency/contacts", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "pick": self.pick(result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pick(_ result: @escaping FlutterResult) {
    if pending != nil {
      result(FlutterError(code: "busy", message: "A contact is already being chosen.", details: nil))
      return
    }
    guard let presenter = Self.topViewController() else {
      result(FlutterError(code: "unavailable", message: "The contacts picker could not open.", details: nil))
      return
    }
    pending = result
    let picker = CNContactPickerViewController()
    picker.delegate = self
    picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
    // Only rows with a number can be chosen; a person with none is not a
    // contact an SOS can ring.
    picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
    presenter.present(picker, animated: true)
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
    guard let number = contactProperty.value as? CNPhoneNumber else {
      settle(nil)
      return
    }
    let name = CNContactFormatter.string(from: contactProperty.contact, style: .fullName) ?? ""
    settle(["name": name, "number": number.stringValue])
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
    // Reached when the contact has exactly one number and iOS skips the
    // property list.
    let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
    let number = contact.phoneNumbers.first?.value.stringValue ?? ""
    settle(number.isEmpty ? nil : ["name": name, "number": number])
  }

  func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
    settle(nil)
  }

  private func settle(_ value: [String: String]?) {
    guard let result = pending else { return }
    pending = nil
    result(value)
  }

  /// Since iOS 13 windows belong to scenes, not the app delegate - which is
  /// the force-unwrap that crashes the package this replaces.
  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
      ?? scenes.flatMap { $0.windows }.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
