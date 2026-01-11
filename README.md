# <img src="TextBlockerApp/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="32" height="32" alt="TextBlocker Icon"> TextBlocker for macOS

A native macOS app that automatically detects and blocks text in videos using Apple's Vision framework.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Native macOS App** - Built with SwiftUI for a beautiful, native experience
- **Vision Framework OCR** - Uses Apple's Vision framework for fast, accurate text detection
- **Smart Frame Skipping** - Perceptual hashing to skip similar frames and speed up processing
- **YouTube Support** - Download and process YouTube videos and playlists
- **Batch Processing** - Process entire folders of videos
- **Drag & Drop** - Simply drag files or folders onto the app
- **Customizable Settings** - Fine-tune detection sensitivity, quality, and more
- **Presets** - Quick settings for different use cases (Fast, Balanced, High Quality)

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3) or Intel Mac
- [Homebrew](https://brew.sh) for dependencies

## Installation

### 1. Install Dependencies

```bash
brew install ffmpeg yt-dlp
```

### 2. Build & Run

1. Clone this repository
2. Open `TextBlockerApp.xcodeproj` in Xcode
3. Build and run (⌘R)

## Usage

### Local Files
1. Click **Files** in the sidebar
2. Drag & drop video files or folders, or click to browse
3. Processing starts automatically

### YouTube Videos
1. Click **YouTube** in the sidebar
2. Paste a YouTube video or playlist URL
3. Toggle "Process as playlist" if needed
4. Click **Process Video**

### Queue
View all processing jobs and their progress in the **Queue** tab.

### Settings
Customize processing in the **Settings** tab:
- **Presets** - Quick configurations (Default, Fast Preview, High Quality, Aggressive)
- **Quality** - Output video quality (Lossless, High, Balanced, Fast)
- **OCR Resolution** - Lower = faster, higher = more accurate
- **Sample Rate** - Frames per second to analyze
- **Box Padding** - Extra padding around detected text
- **Scene Threshold** - Sensitivity to scene changes

## How It Works

1. **Extract Frames** - FFmpeg extracts frames at the configured sample rate
2. **Perceptual Hash** - Each frame is hashed to detect similar frames
3. **Vision OCR** - Apple's Vision framework detects text bounding boxes
4. **Merge & Compress** - Overlapping boxes are merged, time ranges compressed
5. **Apply Filters** - FFmpeg applies black box filters over detected text
6. **Output** - Re-encoded video with text blocked

## Architecture

```
TextBlockerApp/
├── Models/           # Data models
├── Services/         # Core services (FFmpeg, Vision, yt-dlp)
├── ViewModels/       # SwiftUI view models
└── Views/            # SwiftUI views
```

## License

MIT License - see LICENSE file for details.
