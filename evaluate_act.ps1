param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandLineArgs
)

$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

$options = @{
    color = 'red'
    checkpoint = 100000
    numEpisodes = 1
    episodeTimeS = 15
    resetTimeS = 25
}

if ($CommandLineArgs.Count % 2 -ne 0) {
    throw "Arguments must be name/value pairs. Example: .\evaluate_act.ps1 --color red --checkpoint 100000 --num-episodes 1 --episode-time-s 15"
}

for ($index = 0; $index -lt $CommandLineArgs.Count; $index += 2) {
    $argumentName = $CommandLineArgs[$index]
    $argumentValue = $CommandLineArgs[$index + 1]

    switch ($argumentName) {
        '--color' { $options.color = $argumentValue.ToLowerInvariant() }
        '--checkpoint' { $options.checkpoint = [int]$argumentValue }
        '--num-episodes' { $options.numEpisodes = [int]$argumentValue }
        '--episode-time-s' { $options.episodeTimeS = [int]$argumentValue }
        '--reset-time-s' { $options.resetTimeS = [int]$argumentValue }
        default { throw "Unknown argument: $argumentName" }
    }
}

$taskByColor = @{
    red = 'Grab the red bottle cap'
    green = 'Grab the green bottle cap'
    white = 'Grab the white bottle cap'
}

if (-not $taskByColor.ContainsKey($options.color)) {
    throw "Invalid color '$($options.color)'. Use red, green, or white."
}

$supportedCheckpoints = @(20000, 40000, 60000, 80000, 100000)
if ($options.checkpoint -notin $supportedCheckpoints) {
    throw "Invalid checkpoint '$($options.checkpoint)'. Use 20000, 40000, 60000, 80000, or 100000."
}
if ($options.numEpisodes -lt 1 -or $options.episodeTimeS -lt 1 -or $options.resetTimeS -lt 1) {
    throw 'Episode count and time values must be positive integers.'
}

$color = $options.color
$checkpoint = $options.checkpoint
$checkpointDirectory = '{0:D6}' -f $checkpoint
$modelName = "act_bottle_cap_${color}_v1_100k"
$policyPath = Join-Path $PSScriptRoot "outputs\models\$modelName\outputs\train\$modelName\checkpoints\$checkpointDirectory\pretrained_model"
$weightsPath = Join-Path $policyPath 'model.safetensors'

if (-not (Test-Path -LiteralPath $weightsPath -PathType Leaf)) {
    throw "Policy checkpoint not found: $weightsPath"
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$evalName = "eval_bottle_cap_${color}_act${checkpoint}_${timestamp}"
$datasetRoot = Join-Path $PSScriptRoot "outputs\datasets\$evalName"
$datasetRootArgument = $datasetRoot.Replace('\', '/')
$policyPathArgument = $policyPath.Replace('\', '/')

$logDirectory = Join-Path $PSScriptRoot 'outputs\logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logPath = Join-Path $logDirectory "${evalName}.log"

function Write-RunLog {
    param([string]$Message)
    $Message | Tee-Object -FilePath $logPath -Append
}

$sslBootstrap = "import os, ssl, certifi, runpy; os.environ['SSL_CERT_FILE'] = certifi.where(); ssl.SSLContext._windows_cert_stores = (); runpy.run_module('lerobot.record', run_name='__main__')"

$recordArgs = @(
    '--robot.type=so101_follower'
    '--robot.port=COM3'
    '--robot.id=so101_follower_com3'
    '--robot.disable_torque_on_disconnect=true'
    '--robot.max_relative_target=5'
    '--robot.cameras={handeye: {type: opencv, index_or_path: 2, width: 640, height: 480, fps: 30}, front: {type: opencv, index_or_path: 1, width: 640, height: 480, fps: 30}}'
    '--teleop.type=so101_leader'
    '--teleop.port=COM4'
    '--teleop.id=so101_leader_com4'
    "--policy.path=$policyPathArgument"
    '--return_to_start=true'
    '--return_to_start_time_s=5'
    '--display_data=true'
    "--dataset.repo_id=local/$evalName"
    "--dataset.root=$datasetRootArgument"
    "--dataset.num_episodes=$($options.numEpisodes)"
    "--dataset.episode_time_s=$($options.episodeTimeS)"
    "--dataset.reset_time_s=$($options.resetTimeS)"
    "--dataset.single_task=$($taskByColor[$color])"
    '--dataset.push_to_hub=false'
)

$exitCode = 1
try {
    Write-RunLog "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-RunLog "Policy: $policyPath"
    Write-RunLog "Dataset: $datasetRoot"
    Write-RunLog "Evaluation: color=$color checkpoint=$checkpoint episodes=$($options.numEpisodes) episode_time_s=$($options.episodeTimeS) reset_time_s=$($options.resetTimeS)"

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        python -c $sslBootstrap @recordArgs 2>&1 | Tee-Object -FilePath $logPath -Append
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    Write-RunLog "Evaluation process exited with code $exitCode"
}
catch {
    Write-RunLog "ERROR: $($_.Exception.Message)"
    throw
}

exit $exitCode
