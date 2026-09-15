$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

$pythonPath = (Get-Command python -CommandType Application).Source
$teleoperateArgs = @(
    '--robot.type=so101_follower'
    '--robot.port=COM3'
    '--robot.id=so101_follower_com3'
    '--robot.max_relative_target=5'
    '--teleop.type=so101_leader'
    '--teleop.port=COM4'
    '--teleop.id=so101_leader_com4'
    '--fps=30'
    '--display_data=false'
)

& $pythonPath -m lerobot.teleoperate @teleoperateArgs
exit $LASTEXITCODE
