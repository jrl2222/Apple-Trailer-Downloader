# ============================================================
# Apple TV Trailer Downloader
#
# Input:
#   Normal Apple TV movie URL
#
# Example:
#   https://tv.apple.com/us/movie/spirited/umc.cmc....
#
# Output:
#   One MP4 containing:
#       H.264 SDR video
#       English AAC stereo audio
#
# Requires:
#   ffmpeg.exe in the script folder or available in PATH
# ============================================================


# ------------------------------------------------------------
# Settings
# ------------------------------------------------------------

$MaxWidth = 1920



# ------------------------------------------------------------
# Helper: Read HLS attribute
# ------------------------------------------------------------

function Get-HlsAttribute {

    param(
        [string]$Line,
        [string]$Name
    )

    $EscapedName = [regex]::Escape($Name)

    # Quoted attribute
    # Attribute can appear after ":" for the first attribute
    # or after "," for subsequent attributes.
    if ($Line -match "(?:^|[:,])$EscapedName=`"([^`"]*)`"") {
        return $Matches[1]
    }

    # Unquoted attribute
    if ($Line -match "(?:^|[:,])$EscapedName=([^,]*)") {
        return $Matches[1]
    }

    return $null
}


# ------------------------------------------------------------
# Ask for Apple TV movie URL
# ------------------------------------------------------------

Clear-Host

Write-Host "============================================================"
Write-Host "              APPLE TV TRAILER DOWNLOADER"
Write-Host "============================================================"
Write-Host ""

$MovieUrl = Read-Host "Paste Apple TV movie URL"

$MovieUrl = $MovieUrl.Trim()

if ([string]::IsNullOrWhiteSpace($MovieUrl)) {

    Write-Host ""
    Write-Host "ERROR: No URL was entered."
    Read-Host "Press Enter to exit"
    exit 1
}


# ------------------------------------------------------------
# Find FFmpeg
# ------------------------------------------------------------

$LocalFFmpeg = Join-Path $PSScriptRoot "ffmpeg.exe"

if (Test-Path $LocalFFmpeg) {
    $FFmpeg = $LocalFFmpeg
}
else {
    $FFmpegCommand = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue

    if ($FFmpegCommand) {
        $FFmpeg = $FFmpegCommand.Source
    }
    else {
        Write-Host ""
        Write-Host "ERROR: FFmpeg was not found."
        Write-Host ""
        Write-Host "Place ffmpeg.exe in the same folder as this script"
        Write-Host "or install FFmpeg and add it to the system PATH."
        Write-Host ""

        Read-Host "Press Enter to exit"
        exit 1
    }
}

# ------------------------------------------------------------
# Download Apple TV movie page
# ------------------------------------------------------------

Write-Host ""
Write-Host "Downloading Apple TV movie page..."

try {

    $Response = Invoke-WebRequest `
        -Uri $MovieUrl `
        -ErrorAction Stop
}
catch {

    Write-Host ""
    Write-Host "ERROR: Unable to download Apple TV page."
    Write-Host $_.Exception.Message

    Read-Host "Press Enter to exit"
    exit 1
}


# PowerShell 7 can return Content as byte[]
if ($Response.Content -is [byte[]]) {

    $Html = [System.Text.Encoding]::UTF8.GetString(
        $Response.Content
    )
}
else {

    $Html = [string]$Response.Content
}


# ------------------------------------------------------------
# Determine movie title
# ------------------------------------------------------------

$MovieTitle = $null


# First try OpenGraph title
$TitleMatch = [regex]::Match(
    $Html,
    '<meta\s+property="og:title"\s+content="([^"]+)"',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

if ($TitleMatch.Success) {

    $MovieTitle = [System.Net.WebUtility]::HtmlDecode(
        $TitleMatch.Groups[1].Value
    )

    # Usually:
    # Watch Spirited - Movie - Apple TV

    $MovieTitle = $MovieTitle `
    -replace '^Watch\s+', '' `
    -replace '\s+-\s+(?:Movie\s+-\s+)?Apple\s+TV.*$', ''
}


# Fallback
if ([string]::IsNullOrWhiteSpace($MovieTitle)) {

    $MovieTitle = "Apple TV"
}


# Clean invalid filename characters
foreach ($Char in [IO.Path]::GetInvalidFileNameChars()) {

    $MovieTitle = $MovieTitle.Replace(
        [string]$Char,
        '_'
    )
}

$MovieTitle = $MovieTitle.Trim()


# ------------------------------------------------------------
# Find trailer HLS master playlist
#
# Apple currently exposes the normal trailer in:
#
# <meta property="og:video"
#       content="https://play-edge....playlist.m3u8?...">
# ------------------------------------------------------------

$OgVideoMatch = [regex]::Match(
    $Html,
    '<meta\s+property="og:video"\s+content="([^"]+playlist\.m3u8[^"]*)"',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)


if (-not $OgVideoMatch.Success) {

    # Try secure_url as fallback

    $OgVideoMatch = [regex]::Match(
        $Html,
        '<meta\s+property="og:video:secure_url"\s+content="([^"]+playlist\.m3u8[^"]*)"',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
}


if (-not $OgVideoMatch.Success) {

    Write-Host ""
    Write-Host "ERROR: Apple trailer HLS URL was not found."
    Write-Host ""
    Write-Host "Apple may not provide a trailer for this movie, or the page format has changed."

    Read-Host "Press Enter to exit"
    exit 1
}


$MasterUrl = [System.Net.WebUtility]::HtmlDecode(
    $OgVideoMatch.Groups[1].Value
)


Write-Host ""
Write-Host "Movie:"
Write-Host "  $MovieTitle"

Write-Host ""
Write-Host "Trailer master playlist found."


# ------------------------------------------------------------
# Download HLS master playlist
# ------------------------------------------------------------

Write-Host ""
Write-Host "Reading trailer streams..."

try {

    $MasterResponse = Invoke-WebRequest `
        -Uri $MasterUrl `
        -ErrorAction Stop
}
catch {

    Write-Host ""
    Write-Host "ERROR: Unable to read Apple HLS playlist."
    Write-Host $_.Exception.Message

    Read-Host "Press Enter to exit"
    exit 1
}


if ($MasterResponse.Content -is [byte[]]) {

    $MasterText = [System.Text.Encoding]::UTF8.GetString(
        $MasterResponse.Content
    )
}
else {

    $MasterText = [string]$MasterResponse.Content
}


if ($MasterText -notmatch '#EXTM3U') {

    Write-Host ""
    Write-Host "ERROR: Apple did not return a valid HLS playlist."

    Read-Host "Press Enter to exit"
    exit 1
}


$Lines = $MasterText -split "`r?`n"


# ------------------------------------------------------------
# Parse normal video streams
#
# Deliberately ignores:
#   #EXT-X-I-FRAME-STREAM-INF
#
# because those are trick-play / scrub streams.
# ------------------------------------------------------------

$VideoStreams = @()


for ($i = 0; $i -lt $Lines.Count; $i++) {

    $Line = $Lines[$i].Trim()


    if ($Line -notmatch '^#EXT-X-STREAM-INF:') {
        continue
    }


    $Resolution = Get-HlsAttribute $Line 'RESOLUTION'
    $Codecs     = Get-HlsAttribute $Line 'CODECS'
    $VideoRange = Get-HlsAttribute $Line 'VIDEO-RANGE'
    $AudioGroup = Get-HlsAttribute $Line 'AUDIO'
    $Pathway    = Get-HlsAttribute $Line 'PATHWAY-ID'
    $AvgBW      = Get-HlsAttribute $Line 'AVERAGE-BANDWIDTH'
    $Bandwidth  = Get-HlsAttribute $Line 'BANDWIDTH'
    $FrameRate  = Get-HlsAttribute $Line 'FRAME-RATE'


    if ($Resolution -notmatch '^(\d+)x(\d+)$') {
        continue
    }


    $Width  = [int]$Matches[1]
    $Height = [int]$Matches[2]


    # Find playlist URL following EXT-X-STREAM-INF

    $StreamUrl = $null


    for ($j = $i + 1; $j -lt $Lines.Count; $j++) {

        $NextLine = $Lines[$j].Trim()


        if ([string]::IsNullOrWhiteSpace($NextLine)) {
            continue
        }


        if ($NextLine.StartsWith('#')) {
            break
        }


        $StreamUrl = $NextLine
        break
    }


    if (-not $StreamUrl) {
        continue
    }


    $VideoStreams += [PSCustomObject]@{

        Width            = $Width
        Height           = $Height
        Resolution       = $Resolution
        Codecs           = $Codecs
        VideoRange       = $VideoRange
        AudioGroup       = $AudioGroup
        Pathway          = $Pathway

        AverageBandwidth = if ($AvgBW) {
            [long]$AvgBW
        }
        else {
            0
        }

        Bandwidth = if ($Bandwidth) {
            [long]$Bandwidth
        }
        else {
            0
        }

        FrameRate = $FrameRate
        Url       = $StreamUrl
    }
}


# ------------------------------------------------------------
# Select H.264 + SDR
# ------------------------------------------------------------

$Candidates = $VideoStreams |
    Where-Object {

        $_.Codecs -match 'avc1' -and
        $_.VideoRange -eq 'SDR' -and
        $_.Width -le $MaxWidth
    }


if (-not $Candidates) {

    Write-Host ""
    Write-Host "No H.264 SDR stream <= $MaxWidth pixels found."
    Write-Host "Trying any available H.264 SDR stream..."

    $Candidates = $VideoStreams |
        Where-Object {

            $_.Codecs -match 'avc1' -and
            $_.VideoRange -eq 'SDR'
        }
}


if (-not $Candidates) {

    Write-Host ""
    Write-Host "ERROR: No H.264 SDR trailer stream was found."

    Read-Host "Press Enter to exit"
    exit 1
}


# ------------------------------------------------------------
# Select best stream
#
# Priority:
#   highest resolution
#   highest average bitrate
#   Apple AP pathway
# ------------------------------------------------------------

$SelectedVideo = $Candidates |
    Sort-Object -Property `
        @{ Expression = { $_.Width }; Descending = $true },
        @{ Expression = { $_.Height }; Descending = $true },
        @{ Expression = { $_.AverageBandwidth }; Descending = $true },
        @{ Expression = { if ($_.Pathway -eq 'ap') { 1 } else { 0 } }; Descending = $true } |
    Select-Object -First 1


# ------------------------------------------------------------
# Prefer AP pathway if identical stream exists
# ------------------------------------------------------------

$APVersion = $Candidates |
    Where-Object {

        $_.Width -eq $SelectedVideo.Width -and
        $_.Height -eq $SelectedVideo.Height -and
        $_.AverageBandwidth -eq $SelectedVideo.AverageBandwidth -and
        $_.Pathway -eq 'ap'
    } |
    Select-Object -First 1


if ($APVersion) {
    $SelectedVideo = $APVersion
}


# ------------------------------------------------------------
# Parse audio streams
# ------------------------------------------------------------

$AudioStreams = @()


foreach ($Line in $Lines) {

    $Line = $Line.Trim()


    if ($Line -notmatch '^#EXT-X-MEDIA:') {
        continue
    }


    $Type = Get-HlsAttribute $Line 'TYPE'


    if ($Type -ne 'AUDIO') {
        continue
    }


    $AudioStreams += [PSCustomObject]@{

        Name = Get-HlsAttribute $Line 'NAME'

        GroupID = Get-HlsAttribute $Line 'GROUP-ID'

        Language = Get-HlsAttribute $Line 'LANGUAGE'

        Default = Get-HlsAttribute $Line 'DEFAULT'

        Channels = Get-HlsAttribute $Line 'CHANNELS'

        Characteristics = Get-HlsAttribute `
            $Line `
            'CHARACTERISTICS'

        Pathway = Get-HlsAttribute $Line 'PATHWAY-ID'

        Url = Get-HlsAttribute $Line 'URI'
    }
}


# ------------------------------------------------------------
# Select normal English AAC stereo
#
# Video and audio are being downloaded independently, so the
# audio does NOT have to belong to the AUDIO group referenced
# by the selected video variant.
#
# Preference:
#   English
#   AAC
#   Stereo
#   Normal audio (not descriptive/DVS)
#   DEFAULT=YES
#   Apple "ap" pathway
# ------------------------------------------------------------

$AudioCandidates = $AudioStreams |
    Where-Object {

        # English can be "en", "en-US", etc.
        $_.Language -match '^en(?:[-_]|$)' -and

        # Must actually have a playlist
        -not [string]::IsNullOrWhiteSpace($_.Url) -and

        # Exclude descriptive-video / DVS audio
        $_.Characteristics -notmatch 'describes-video' -and
        $_.Url -notmatch '_dvs_'
    }


# Prefer AAC stereo tracks.
$AacStereoCandidates = $AudioCandidates |
    Where-Object {

        $_.Channels -eq '2' -and

        (
            $_.Url -match 'mp4a' -or
            $_.GroupID -match 'stereo'
        )
    }


if ($AacStereoCandidates) {
    $AudioCandidates = $AacStereoCandidates
}


$SelectedAudio = $AudioCandidates |
    Sort-Object -Property `
        @{ Expression = { if ($_.Default -eq 'YES') { 1 } else { 0 } }; Descending = $true },
        @{ Expression = { if ($_.Pathway -eq 'ap') { 1 } else { 0 } }; Descending = $true },
        @{ Expression = { if ($_.GroupID -match 'stereo-160') { 1 } else { 0 } }; Descending = $true } |
    Select-Object -First 1


if (-not $SelectedAudio) {

    Write-Host ""
    Write-Host "ERROR: Normal English audio was not found."
    Write-Host ""
    Write-Host "Audio tracks Apple reported:"
    Write-Host ""

    $AudioStreams |
        Select-Object Name, Language, Channels, Default, GroupID, Pathway, Url |
        Format-Table -AutoSize

    Read-Host "Press Enter to exit"
    exit 1
}


# ------------------------------------------------------------
# Display selected streams
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================================"
Write-Host "                    TRAILER FOUND"
Write-Host "============================================================"

Write-Host ""
Write-Host "Movie       : $MovieTitle"

Write-Host ""
Write-Host "VIDEO"
Write-Host "Resolution  : $($SelectedVideo.Resolution)"
Write-Host "Frame Rate  : $($SelectedVideo.FrameRate)"
Write-Host "Range       : $($SelectedVideo.VideoRange)"

if ($SelectedVideo.AverageBandwidth -gt 0) {

    $Mbps = [math]::Round(
        $SelectedVideo.AverageBandwidth / 1000000,
        2
    )

    Write-Host "Avg Bitrate : $Mbps Mbps"
}

Write-Host "Pathway     : $($SelectedVideo.Pathway)"


Write-Host ""
Write-Host "AUDIO"
Write-Host "Name        : $($SelectedAudio.Name)"
Write-Host "Language    : $($SelectedAudio.Language)"
Write-Host "Channels    : $($SelectedAudio.Channels)"
Write-Host "Pathway     : $($SelectedAudio.Pathway)"


# ------------------------------------------------------------
# Ask where to save the trailer
# ------------------------------------------------------------

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SaveDialog = New-Object System.Windows.Forms.SaveFileDialog

$SaveDialog.Title = "Save Apple TV Trailer"
$SaveDialog.Filter = "MP4 Video (*.mp4)|*.mp4"
$SaveDialog.DefaultExt = "mp4"
$SaveDialog.AddExtension = $true
$SaveDialog.FileName = "$MovieTitle Trailer.mp4"
$SaveDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
$SaveDialog.OverwritePrompt = $true

# Create an invisible top-most owner window so the
# Save As dialog always appears in front.
$Owner = New-Object System.Windows.Forms.Form
$Owner.TopMost = $true
$Owner.ShowInTaskbar = $false
$Owner.StartPosition = 'CenterScreen'
$Owner.Size = New-Object System.Drawing.Size(1, 1)
$Owner.Opacity = 0

$Owner.Show()
$Owner.Activate()

$DialogResult = $SaveDialog.ShowDialog($Owner)

$Owner.Close()
$Owner.Dispose()

if ($DialogResult -ne [System.Windows.Forms.DialogResult]::OK) {

    Write-Host ""
    Write-Host "Save cancelled."
    Read-Host "Press Enter to exit"
    exit
}

$OutputFile = $SaveDialog.FileName

# ------------------------------------------------------------
# Download and mux
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================================"
Write-Host "                    DOWNLOADING"
Write-Host "============================================================"

Write-Host ""
Write-Host "Output:"
Write-Host $OutputFile
Write-Host ""


$FFmpegArgs = @(
    '-hide_banner'
    '-i'
    $SelectedVideo.Url
    '-i'
    $SelectedAudio.Url
    '-map'
    '0:v:0'
    '-map'
    '1:a:0'
    '-c'
    'copy'
    '-movflags'
    '+faststart'
    '-y'
    $OutputFile
)

& $FFmpeg @FFmpegArgs


# ------------------------------------------------------------
# Check result
# ------------------------------------------------------------

if ($LASTEXITCODE -ne 0) {

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "                       FAILED"
    Write-Host "============================================================"

    Write-Host ""
    Write-Host "FFmpeg returned exit code $LASTEXITCODE."

    Read-Host "Press Enter to exit"
    exit $LASTEXITCODE
}


if (-not (Test-Path $OutputFile)) {

    Write-Host ""
    Write-Host "ERROR: FFmpeg completed but output file was not found."

    Read-Host "Press Enter to exit"
    exit 1
}


$FileSize = (Get-Item $OutputFile).Length

$FileSizeMB = [math]::Round(
    $FileSize / 1MB,
    2
)


Write-Host ""
Write-Host "============================================================"
Write-Host "                       COMPLETE"
Write-Host "============================================================"

Write-Host ""
Write-Host "File:"
Write-Host $OutputFile

Write-Host ""
Write-Host "Size:"
Write-Host "$FileSizeMB MB"

Write-Host ""
