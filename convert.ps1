# Path to the extracte listenbrainz archive
$listenbrainzExportPath = Get-Item -Path ".\listenbrainz_joestr_1738750872"

# exclusive boundary > for when to start converting
$importFromTimestamp = Get-Date -Year 2024 -Month 12 -Day 31

# exclusive boundary < for when to stop converting
$importToTimestamp = Get-Date -Year 2025 -Month 02 -Day 1

$doesListensFolderExists = Test-Path -Path "$listenbrainzExportPath/listens"

class SpotifyEndSongImportModel {
    [datetime] $TimeStampUtc
    [int] $MilliSecondsPlayed
    [string] $TrackName
    [string] $AlbumArtistName
    [string] $AlbumAlbumName
}

if ($doesListensFolderExists -eq $false) {
    Write-Error "There is no folder `"listens`" in the export folder."
    exit 1
}

$candidateYearListensFolders = @()
$yearListensFolders = Get-ChildItem -Directory -Path "$listenbrainzExportPath/listens"
foreach ($yearListensFolder in $yearListensFolders) {
    $folderName = $yearListensFolder.Name
    $folderNameInt = 0
    $folderNameIntSuccess = [int]::TryParse($folderName, [ref]$folderNameInt)

    if ($folderNameIntSuccess -eq $false) {
        Write-Error "Failed to convert folder name `"$folderName`" to integer."
        exit 1
    }

    if ($folderNameInt -ge $importFromTimestamp.Year -and $folderNameInt -le $importToTimestamp.Year) {
        $candidateYearListensFolders += $yearListensFolder
    }
}

$candidateMonthListensFiles = @()
foreach ($candidateYearListensFolder in $candidateYearListensFolders) {
    $monthListensFiles = Get-ChildItem -File -Path $candidateYearListensFolder.FullName
    foreach ($monthListensFile in $monthListensFiles) {
        $fileName = $monthListensFile.BaseName
        $fileNameInt = 0
        $fileNameIntSuccess = [int]::TryParse($fileName, [ref]$fileNameInt)

        if ($fileNameIntSuccess -eq $false) {
            Write-Error "Failed to convert file name `"$fileName`" to integer."
            exit 1
        }

        $candidateMonthListensFiles += $monthListensFile
    }
}


$jsonListens = @()
foreach ($listensFile in $candidateMonthListensFiles) {
    $jsonListen = Get-Content -Path $listensFile | ConvertFrom-Json
    $jsonListens += $jsonListen
}

$spotifyExports = @()
foreach ($listen in $jsonListens) {
    $entry = [SpotifyEndSongImportModel]::new()
    $entry.TimeStampUtc = Get-Date -UnixTimeSeconds $listen.listened_at

    if ($entry.TimeStampUtc.Date -gt $importFromTimestamp.Date -and $entry.TimeStampUtc.Date -lt $importToTimestamp.Date) {
        $entry.TrackName = $listen.track_metadata.track_name
        $entry.AlbumAlbumName = $listen.track_metadata.release_name
        $entry.AlbumArtistName = $listen.track_metadata.artist_name
        $entry.MilliSecondsPlayed = $listen.track_metadata.additional_info.duration_ms

        if ($null -eq $entry.AlbumAlbumName -or $null -eq $entry.AlbumArtistName) {
            $reqData = Invoke-WebRequest -Uri "https://musicbrainz.org/ws/2/release/" + $listen.track_metadata.mbid_mapping.release_mbid + "?inc=artists&fmt=json"
            $reqDataJson = $reqData.Content | ConvertFrom-Json
            $entry.AlbumAlbumName = $reqDataJson.title
            $varArtist = ""
            $reqDataJson.'artist-credit' | Select-Object -Property name,joinphrase | ForEach-Object { $varArtist += $_.name + $_.joinphrase }
            $entry.AlbumArtistName = $varArtist
        }

        if ($null -eq $entry.MilliSecondsPlayed -or $null -eq $entry.TrackName) {
            $reqData = Invoke-WebRequest -Uri "https://musicbrainz.org/ws/2/recording/" + $listen.track_metadata.mbid_mapping.recording_mbid + "?fmt=json"
            $reqDataJson = $reqData.Content | ConvertFrom-Json
            $entry.MilliSecondsPlayed = $reqDataJson.length
            $entry.TrackName = $reqDataJson.title
        }

        $spotifyExports += $entry
    }
}

$realExports = @()
foreach ($spotifyExport in $spotifyExports) {
    $entry = @{}
    $entry.ts = $spotifyExport.TimeStampUtc
    $entry.ms_played = $spotifyExport.MilliSecondsPlayed
    $entry.master_metadata_track_name = $spotifyExport.TrackName
    $entry.master_metadata_album_artist_name = $spotifyExport.AlbumArtistName
    $entry.master_metadata_album_album_name = $spotifyExport.AlbumAlbumName
    $realExports += $entry
}

$realExports | ConvertTo-Json | Out-File "export.json"

