param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandLineArgs
)

$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

if (
    $CommandLineArgs.Count -ne 4 -or
    $CommandLineArgs[0] -ne '--name' -or
    $CommandLineArgs[2] -ne '--task'
) {
    throw ".\record_demo.ps1 --name bottle_cap_white_v1 --task 'Grab the white bottle cap'"
}

$datasetName = $CommandLineArgs[1]
if ($datasetName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Invalid dataset name '$datasetName'. Use only letters, numbers, dots, underscores, and hyphens."
}
$taskName = $CommandLineArgs[3].Trim()
if (-not $taskName) {
    throw 'Task description cannot be empty.'
}

$datasetRoot = Join-Path $PSScriptRoot "outputs\datasets\$datasetName"
$datasetRootArgument = $datasetRoot.Replace('\', '/')

$logDirectory = Join-Path $PSScriptRoot 'outputs\logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path $logDirectory "record_${datasetName}_${timestamp}.log"

function Write-RunLog {
    param([string]$Message)
    $Message | Tee-Object -FilePath $logPath -Append
}

$sslBootstrap = "import os, ssl, certifi, runpy; os.environ['SSL_CERT_FILE'] = certifi.where(); ssl.SSLContext._windows_cert_stores = (); runpy.run_module('lerobot.record', run_name='__main__')"

$recordArgs = @(
    '--robot.type=so101_follower'
    '--robot.port=COM3'
    '--robot.id=so101_follower_com3'
    '--robot.max_relative_target=5'
    '--robot.cameras={handeye: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 30}, front: {type: opencv, index_or_path: 2, width: 640, height: 480, fps: 30}}'
    '--teleop.type=so101_leader'
    '--teleop.port=COM4'
    '--teleop.id=so101_leader_com4'
    '--display_data=true'
    "--dataset.repo_id=local/$datasetName"
    "--dataset.root=$datasetRootArgument"
    '--dataset.num_episodes=25'
    '--dataset.episode_time_s=60'
    '--dataset.reset_time_s=25'
    "--dataset.single_task=$taskName"
    '--dataset.push_to_hub=false'
)

$exitCode = 1
try {
    Write-RunLog "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-RunLog "Log file: $logPath"

    if (Test-Path -LiteralPath $datasetRoot) {
        throw "Dataset already exists: $datasetRoot. Choose a new --name value."
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        python -c $sslBootstrap @recordArgs 2>&1 | Tee-Object -FilePath $logPath -Append
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        Write-RunLog "Recording process exited with code $exitCode"
    }
}
catch {
    Write-RunLog "ERROR: $($_.Exception.Message)"
    throw
}

exit $exitCode
