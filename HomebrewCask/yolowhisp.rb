cask "yolowhisp" do
  version :latest
  sha256 :no_check

  url "https://github.com/YOLOVibeCode/yolowhisp/releases/latest/download/YOLOWhisp-#{version}-macOS.zip"
  name "YOLOWhisp"
  desc "Fully local speech-to-text for macOS, powered by whisper-cpp + Metal GPU"
  homepage "https://github.com/YOLOVibeCode/yolowhisp"

  depends_on formula: "whisper-cpp"
  depends_on macos: ">= :sonoma"

  app "YOLOWhisp.app"

  postflight do
    # Create model directory
    system_command "/bin/mkdir", args: ["-p", "#{Dir.home}/.local/share/whisper"]
  end

  zap trash: [
    "~/Library/Application Support/YOLOWhisp",
    "~/Library/Preferences/com.yolovibecode.yolowhisp.plist",
  ]
end
