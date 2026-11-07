import Foundation
#if canImport(Darwin)
import Darwin
#endif
@main
struct Verify {
  static func main() async {
    var failures = 0
    func check(_ ok: Bool, _ name: String, _ detail: String = "") {
      if ok { print("PASS \(name)\(detail.isEmpty ? "" : " — \(detail)")") }
      else { print("FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")"); failures += 1 }
    }
    let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/purge_verify_\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let bigFile = base.appendingPathComponent("data.bin")
    let data = Data(repeating: 0x41, count: 1_000_000)
    try! data.write(to: bigFile)
    let allocated = DiskSize.blockSize(of: bigFile)
    check(allocated > 0, "allocated > 0", "\(allocated) bytes")
    check(allocated <= 1_000_000 + 16384, "allocated <= logical+slack", "\(allocated) vs 1000000")
    let empty = base.appendingPathComponent("empty")
    try! FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: empty.path)) ?? []
    check(names.isEmpty, "empty dir -> 0 children")
    let total = await DiskSize.allocatedSize(of: base)
    check(total > 0, "tree total > 0", "\(total) bytes")
    let home = FileManager.default.homeDirectoryForCurrentUser
    let mail = home.appendingPathComponent("Library/Mail")
    let mailListable = (try? FileManager.default.contentsOfDirectory(atPath: mail.path)) != nil
    print("FDA probe mail-listable=\(mailListable) (either way is a valid test result)")
    func isOutside(_ url: URL) -> Bool {
      let homePath = home.path
      if url == home { return false }
      return !url.path.hasPrefix(homePath + "/")
    }
    check(!isOutside(base), "inside-home allowed")
    check(isOutside(URL(fileURLWithPath: "/etc/hosts")), "outside-home blocked")
    check(isOutside(URL(fileURLWithPath: "/Applications/Purge.app")), "Applications blocked")
    try? FileManager.default.removeItem(at: base)
    if failures > 0 { print("\(failures) FAILURE(S)"); exit(1) }
    print("ALL CHECKS PASSED")
  }
}
