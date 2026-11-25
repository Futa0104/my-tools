param(
    [Parameter(Mandatory)]
    [ValidateSet('Setup', 'Apply', 'Startup', 'StopStartup')]
    [string]$Action,
    [switch]$Hidden
)

$ErrorActionPreference = 'Stop'
$toolFolder = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $toolFolder 'config.txt'
$localConfigPath = Join-Path $toolFolder 'config.local.txt'
if ([IO.File]::Exists($localConfigPath)) { $configPath = $localConfigPath }
$configName = [IO.Path]::GetFileName($configPath)
$localAppData = [Environment]::GetFolderPath('LocalApplicationData')
$dataFolder = Join-Path $localAppData 'MyTools\MonitorWallpaper'
$startupFolder = [Environment]::GetFolderPath('Startup')
$startupPath = Join-Path $startupFolder 'My Tools Monitor Wallpaper.lnk'
$legacyStartupPath = Join-Path $startupFolder 'Freely Monitor Wallpaper.lnk'
$legacyLauncherPath = Join-Path $localAppData 'Freely\MonitorWallpaper\MonitorWallpaper.exe'
$menuPath = Join-Path ([Environment]::GetFolderPath('Programs')) '壁紙を引き直す.lnk'
$launcherPath = Join-Path $dataFolder 'MonitorWallpaper.exe'

function Read-MonitorSettings {
    $settings = @{}
    $lineNumber = 0
    foreach ($rawLine in Get-Content -LiteralPath $configPath -Encoding UTF8) {
        $lineNumber++
        $line = $rawLine.Trim()
        if (!$line -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^((?:Monitor|Folder)([1-9][0-9]*))\s*=\s*(.*)$') {
            throw "$configName の ${lineNumber} 行目を確認してください。"
        }
        $key = $Matches[1]
        $number = 0
        if (![int]::TryParse($Matches[2], [ref]$number)) {
            throw "$configName の ${lineNumber} 行目の画面番号を確認してください。"
        }
        if ($settings.ContainsKey($key)) { throw "$configName に $key が2回書かれています。" }
        $settings[$key] = $Matches[3].Trim().Trim('"')
    }

    $numbers = @(
        foreach ($key in $settings.Keys) {
            if ($key -match '^Monitor([0-9]+)$') {
                [int]$Matches[1]
            } elseif ($key -match '^Folder([0-9]+)$' -and !$settings.ContainsKey("Monitor$($Matches[1])")) {
                throw "$configName に Monitor$($Matches[1]) がありません。"
            }
        }
    )
    if ($numbers.Count -eq 0) { throw "$configName に Monitor1 などの画面番号を書いてください。" }

    foreach ($number in ($numbers | Sort-Object)) {
        $mode = $settings["Monitor$number"]
        if ($mode -notin 'random', 'keep') {
            throw "$configName の Monitor$number に random または keep を書いてください。"
        }
        $folder = $settings["Folder$number"]
        if ($mode -eq 'random' -and $folder -notmatch '^(?:[A-Za-z]:[\\/]|\\\\)') {
            throw "$configName の Folder$number に、C:\ から始まるようなフォルダーの場所を入力してください。"
        }
        [pscustomobject]@{ Number = $number; Mode = $mode; Folder = $folder }
    }
}

function Get-ImageFiles($setting) {
    $folder = $setting.Folder
    if (!(Test-Path -LiteralPath $folder -PathType Container)) {
        throw "フォルダーが見つかりません ($folder)。$configName の Folder$($setting.Number) を確認してください。"
    }
    $files = @(Get-ChildItem -LiteralPath $folder -File | Where-Object Extension -in '.jpg', '.jpeg', '.jfif', '.png', '.bmp')
    if ($files.Count -eq 0) {
        throw "フォルダーの直下に使える画像がありません ($folder)。JPG、JPEG、JFIF、PNG、BMP が使えます。"
    }
    $files
}

function Remove-StartupShortcut($path, $target) {
    if (![IO.File]::Exists($path)) { return }

    $shell = New-Object -ComObject WScript.Shell
    if ($shell.CreateShortcut($path).TargetPath -eq $target) {
        [IO.File]::Delete($path)
    }
}

function Install-Shortcuts {
    New-Item -Path $dataFolder -ItemType Directory -Force | Out-Null
    $temporaryLauncher = Join-Path $dataFolder ("MonitorWallpaper-{0}.exe" -f [Guid]::NewGuid())
    try {
        Add-Type -LiteralPath (Join-Path $PSScriptRoot 'Launcher.cs') -ReferencedAssemblies 'System.Windows.Forms.dll' `
            -OutputAssembly $temporaryLauncher -OutputType WindowsApplication
        if ([IO.File]::Exists($launcherPath)) {
            [IO.File]::Replace($temporaryLauncher, $launcherPath, [NullString]::Value)
        } else {
            [IO.File]::Move($temporaryLauncher, $launcherPath)
        }
    } finally {
        if ([IO.File]::Exists($temporaryLauncher)) { [IO.File]::Delete($temporaryLauncher) }
    }

    $shell = New-Object -ComObject WScript.Shell
    foreach ($entry in @(@{ Path = $menuPath; Mode = 'Apply' }, @{ Path = $startupPath; Mode = 'Startup' })) {
        $shortcut = $shell.CreateShortcut($entry.Path)
        $shortcut.TargetPath = $launcherPath
        $shortcut.Arguments = '"{0}" {1}' -f $PSCommandPath, $entry.Mode
        $shortcut.WorkingDirectory = $PSScriptRoot
        $shortcut.Description = 'モニターごとの設定に従って壁紙を引き直します。'
        $shortcut.Save()
    }
    Remove-StartupShortcut $legacyStartupPath $legacyLauncherPath
}

function Set-RandomWallpaper($desktop, $monitor, $setting) {
    $files = @(Get-ImageFiles $setting)
    $current = $desktop.GetWallpaper($monitor.Id)
    $choices = @($files | Where-Object FullName -ne $current)
    if ($choices.Count -eq 0) {
        return "候補が1枚のため現在の壁紙を使います ($current)。"
    }

    $lastError = $null
    foreach ($image in Get-Random -InputObject $choices -Count $choices.Count) {
        try {
            $desktop.SetWallpaper($monitor.Id, $image.FullName)
            $applied = $desktop.GetWallpaper($monitor.Id)
            if ($applied -ne $image.FullName) { throw "$($image.FullName) が壁紙に設定されたことを確認できませんでした。" }
            return "壁紙を変更しました ($applied)。"
        } catch {
            $lastError = $_.Exception.Message
        }
    }
    throw "画像を壁紙にできませんでした。$lastError"
}

$logName = if ($Action -eq 'Startup') { 'last-startup.txt' } else { 'last-reroll.txt' }
$logPath = Join-Path $dataFolder $logName
$records = [System.Collections.Generic.List[string]]::new()
$errors = [System.Collections.Generic.List[string]]::new()
$recordRun = $Action -in 'Apply', 'Startup'
# Share the lock with copies that were still launched from the old shortcuts.
$mutex = [Threading.Mutex]::new($false, 'Local\Freely.MonitorWallpaper')
$locked = $false

try {
    try {
        $locked = $mutex.WaitOne(30000)
    } catch [Threading.AbandonedMutexException] {
        $locked = $true
    }
    if (!$locked) { throw '壁紙ランダムが実行中です。少し待ってからもう一度お試しください。' }

    if ($Action -eq 'StopStartup') {
        Remove-StartupShortcut $startupPath $launcherPath
        Remove-StartupShortcut $legacyStartupPath $legacyLauncherPath
        $records.Add('サインイン時の自動実行を止めました。')
    } else {
        $settings = @(Read-MonitorSettings)
        $randomSettings = @($settings | Where-Object Mode -eq random)

        if ($Action -eq 'Setup') {
            foreach ($setting in $randomSettings) { $null = Get-ImageFiles $setting }
            Install-Shortcuts
            $records.Add('設定できました。次回の Windows サインイン時に壁紙を引き直します。')
            $records.Add('今すぐ試すには Reroll.bat、タスクバーに置くには readme.txt を開いてください。')
        } elseif ($randomSettings.Count -eq 0) {
            $records.Add('すべてのモニターが keep の設定です。')
        } else {
            Add-Type -LiteralPath (Join-Path $PSScriptRoot 'DesktopWallpaper.cs')
            $desktop = [MyTools.MonitorWallpaper.DesktopWallpaper]::new()
            try {
                $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
                $background = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).BackgroundType
                if (($null -ne $background -and $background -ne 0) -or $desktop.UsesSlideshow -or $desktop.UsesSpan) {
                    throw 'Windows の「設定 → 個人用設定 → 背景」で「画像」を選び、合わせ方は「画面に合わせる」など、全画面にまたがらない設定にしてください。'
                }

                $deadline = [DateTime]::UtcNow.AddSeconds(20)
                do {
                    $monitors = @($desktop.GetMonitors())
                    $missing = @($randomSettings | Where-Object { $_.Number -notin $monitors.Number })
                    if ($Action -ne 'Startup' -or $missing.Count -eq 0 -or [DateTime]::UtcNow -ge $deadline) { break }
                    Start-Sleep -Seconds 1
                } while ($true)

                foreach ($setting in $settings) {
                    $label = "モニター $($setting.Number)"
                    if ($setting.Mode -eq 'keep') {
                        $records.Add("${label} は keep に設定されています。")
                        continue
                    }

                    try {
                        $target = @($monitors | Where-Object Number -eq $setting.Number)
                        if ($target.Count -ne 1) {
                            throw '対象を特定できません。「設定 → システム → ディスプレイ → 識別」と「表示画面を拡張する」を確認してください。'
                        }
                        $message = Set-RandomWallpaper $desktop $target[0] $setting
                        $records.Add("${label} の$message")
                    } catch {
                        $errors.Add("${label} の処理に失敗しました。$($_.Exception.Message)")
                    }
                }
            } finally {
                $desktop.Dispose()
            }
        }
    }
} catch {
    $errors.Add($_.Exception.Message)
} finally {
    if ($recordRun -and $locked) {
        try {
            New-Item -Path $dataFolder -ItemType Directory -Force | Out-Null
            $trigger = if ($Action -eq 'Startup') { 'Windows サインイン時' } else { '手動' }
            $report = @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'), $trigger) + $records.ToArray() + $errors.ToArray()
            [IO.File]::WriteAllLines($logPath, [string[]]$report, [Text.UTF8Encoding]::new($true))
        } catch {
            $errors.Add("実行記録を保存できませんでした。$($_.Exception.Message)")
        }
    }
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

if (!$Hidden) {
    foreach ($line in $records) { Write-Host $line }
    foreach ($line in $errors) { Write-Host $line -ForegroundColor Red }
} elseif ($Action -eq 'Apply' -and $errors.Count -gt 0) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show(($errors -join "`r`n"), '壁紙ランダム', 'OK', 'Warning')
}
if ($errors.Count -gt 0) { exit 1 }
