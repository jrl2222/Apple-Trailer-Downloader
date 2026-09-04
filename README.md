# Apple TV Trailer Downloader

A PowerShell script for downloading trailers directly from Apple TV and saving them as MP4 files.

The script automatically finds the trailer stream, selects H.264 SDR video with English stereo audio, and uses FFmpeg to combine the video and audio without re-encoding.

## Features

- Downloads trailers directly from Apple TV
- Automatically detects the trailer from a normal Apple TV movie URL
- Selects H.264 SDR video
- Selects English stereo audio
- Excludes descriptive/DVS audio
- Uses FFmpeg stream copy — no video or audio re-encoding
- Saves the finished trailer as a standard MP4
- Provides a Windows **Save As** dialog to choose the filename and location

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or PowerShell 7+
- FFmpeg (`ffmpeg.exe`)
- Internet connection

### FFmpeg

Place `ffmpeg.exe` in the same folder as `Download-AppleTrailer.ps1`, or install FFmpeg and make sure it is available in your system `PATH`.

## Video Quality

The script currently chooses the best available **H.264 SDR** stream at or below **1920 pixels wide**, which generally means up to 1080p.

Apple may provide higher-resolution HEVC, HDR, or 4K versions of some trailers, but this script intentionally uses H.264 SDR for broad compatibility.

I primarily use these trailers with a Jellyfin server, where 1080p H.264 provides excellent quality and compatibility.

## Usage

### 1. Find a movie on Apple TV

Go to `tv.apple.com` and find the movie you want.

### 2. Copy the main movie URL

For example, **School of Rock**:

```text
https://tv.apple.com/us/movie/school-of-rock/umc.cmc.im6cmmj5czmu1lrpj820whud
```

You can get the URL in one of two ways:

- Right-clicking the movie cover and selecting **Copy Link** 
- Opening the movie page and copying the URL from your browser's address bar
  
<img width="640" alt="image" src="https://github.com/jrl2222/Apple-Trailer-Downloader/blob/main/images/CopyLink.png" /><img width="640" alt="image" src="https://github.com/jrl2222/Apple-Trailer-Downloader/blob/main/images/CopyUrl.png" />

### 3. Run the PowerShell script

Run:

```text
Download-AppleTrailer.ps1
```

### 4. Paste the Apple TV URL

When prompted, paste the movie URL and press **Enter**.

The script will locate the trailer and determine the best compatible video and audio streams.

### 5. Choose where to save the trailer

A Windows **Save As** dialog will open.

Choose the destination folder and change the filename if desired.

The default filename is based on the movie title:

```text
School of Rock Trailer.mp4
```

### 6. Download

FFmpeg downloads the separate Apple video and audio streams and combines them into a single MP4 without re-encoding.

<img width="640" alt="image" src="https://github.com/jrl2222/Apple-Trailer-Downloader/blob/main/images/Running.png" />

When complete, the script displays the saved filename and file size.

## Jellyfin

The downloaded MP4 can be used as a local Jellyfin trailer.

One common folder layout is:

```text
Movies
└── School of Rock (2003)
    ├── School of Rock (2003).mkv
    └── trailers
        └── School of Rock Trailer.mp4
```

After adding the trailer, scan the Jellyfin library so Jellyfin detects the new file.

## Notes

- Trailer availability depends on Apple providing a trailer for the selected title.
- Apple can change its website or HLS playlist format at any time, which may require changes to this script.
- The script currently targets H.264 SDR rather than HEVC/HDR streams.
- Video and audio are copied directly into the MP4 container without re-encoding.

## License

This project is licensed under the GNU General Public License v3.0. See the `LICENSE` file for details.

## Disclaimer

This project is not affiliated with, endorsed by, or sponsored by Apple Inc.

Apple TV and related trademarks are the property of their respective owners.

Users are responsible for ensuring their use of downloaded content complies with applicable laws and the terms of the content provider.
