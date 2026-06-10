import Foundation

/// Pure detector for RDP, VM, and remote desktop clients. Used to switch
/// typing strategy from Unicode injection (fails over RDP) to hardware-
/// faithful key-code emulation (works reliably across remote sessions).
public struct RemoteSessionDetector {
    /// Bundle identifier prefixes for known remote/VM clients.
    private static let remoteBundlePrefixes: [String] = [
        "com.microsoft.rdc",       // Microsoft Remote Desktop, Windows App
        "com.parallels",            // Parallels Desktop (console + coherence apps)
        "com.vmware.fusion",        // VMware Fusion
        "com.vmware.horizon",       // VMware Horizon Client
        "com.citrix",               // Citrix Receiver/Workspace
        "com.p5sys.jump",           // Jump Desktop
        "com.teamviewer",           // TeamViewer
        "com.realvnc",              // RealVNC
        "com.thinomecloud"          // Amazon WorkSpaces
    ]
    
    /// App name substrings for fallback detection when bundle ID is unavailable.
    private static let remoteNameSubstrings: [String] = [
        "Remote Desktop",
        "Windows App",
        "Parallels",
        "VMware",
        "Citrix",
        "Jump Desktop",
        "TeamViewer",
        "VNC"
    ]
    
    /// Returns true if the given bundle identifier or app name matches a known
    /// remote/VM client. Bundle ID matching is preferred (more reliable); name
    /// matching is a fallback for apps without a detectable bundle.
    public static func isRemote(bundleId: String?, name: String?) -> Bool {
        // Primary: bundle identifier prefix match
        if let bundle = bundleId {
            for prefix in remoteBundlePrefixes {
                if bundle.hasPrefix(prefix) {
                    return true
                }
            }
        }
        
        // Fallback: app name substring match
        if let appName = name {
            for substring in remoteNameSubstrings {
                if appName.localizedCaseInsensitiveContains(substring) {
                    return true
                }
            }
        }
        
        return false
    }
}
