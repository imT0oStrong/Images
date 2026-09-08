#Requires -RunAsAdministrator

# ============================================================
# Installe l'auto-partage de connexion : crée le script cible
# + l'enregistre dans le planificateur de tâches (au logon)
# ============================================================

$InstallDir = "C:\"
$ScriptPath = Join-Path $InstallDir "StartHotspot.ps1"
$TaskName   = "AutoHotspot"

# 1. Créer le dossier d'installation si besoin
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# 2. Écrire le script de partage de connexion
$TetheringScript = @'
function Await-WinRTAction {
    param($AsyncAction)
    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.IsGenericMethod
    })[0]
    $resultType = $AsyncAction.GetType().GetInterface('IAsyncOperation`1').GetGenericArguments()[0]
    $asTask = $asTaskGeneric.MakeGenericMethod($resultType)
    $task = $asTask.Invoke($null, @($AsyncAction))
    $task.Wait(-1) | Out-Null
    return $task.Result
}

try {
    $Profile = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()

    if (-not $Profile) {
        Write-Output "Aucune connexion internet active trouvee. Partage impossible."
        exit 1
    }

    $Manager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]::CreateFromConnectionProfile($Profile)

    if ($Manager.TetheringOperationalState -eq 1) {
        Write-Output "Le partage de connexion est deja actif."
        exit 0
    }

    $result = Await-WinRTAction $Manager.StartTetheringAsync()
    Write-Output "Statut du partage : $($result.Status)"
}
catch {
    Write-Output "Erreur : $($_.Exception.Message)"
    exit 1
}
'@

Set-Content -Path $ScriptPath -Value $TetheringScript -Encoding UTF8 -Force

# 3. Créer / mettre à jour la tâche planifiée
$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""

$Trigger   = New-ScheduledTaskTrigger -AtLogOn
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$Settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $TaskName `
    -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null

Write-Output "Installation terminee."
Write-Output "Script cree ici : $ScriptPath"
Write-Output "Tache planifiee '$TaskName' active : le partage demarrera a chaque ouverture de session."
