#!/usr/bin/env bash
set -euo pipefail

ROOT=/root/autodl-tmp
cd "$ROOT"

tar -xf autodl_bottle_cap_green_merged_v1.tar
tar -xf autodl_bottle_cap_white_merged_v1.tar

/root/miniconda3/bin/python -c "from lerobot.datasets.lerobot_dataset import LeRobotDataset; d=LeRobotDataset('local/bottle_cap_green_merged_v1', root='$ROOT/bottle_cap_green_merged_v1'); assert d.num_episodes == 25; print('green', d.num_episodes, len(d))"
/root/miniconda3/bin/python -c "from lerobot.datasets.lerobot_dataset import LeRobotDataset; d=LeRobotDataset('local/bottle_cap_white_merged_v1', root='$ROOT/bottle_cap_white_merged_v1'); assert d.num_episodes == 25; print('white', d.num_episodes, len(d))"

chmod +x "$ROOT/autodl_train_green_white_runner.sh"
screen -dmS act_green_white "$ROOT/autodl_train_green_white_runner.sh"
screen -ls
