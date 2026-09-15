#!/usr/bin/env bash
set -u

ROOT=/root/autodl-tmp
LEROBOT_DIR="$ROOT/lerobot"

run_training() {
    local color="$1"
    local dataset_name="$2"
    local output_name="act_bottle_cap_${color}_v1_100k"
    local log_path="$ROOT/${output_name}.log"

    cd "$LEROBOT_DIR" || return 1
    PYTHONUNBUFFERED=1 /root/miniconda3/bin/lerobot-train \
        --dataset.repo_id="local/${dataset_name}" \
        --dataset.root="$ROOT/${dataset_name}" \
        --dataset.video_backend=pyav \
        --policy.type=act \
        --policy.device=cuda \
        --policy.push_to_hub=false \
        --wandb.enable=false \
        --output_dir="$ROOT/outputs/train/${output_name}" \
        --job_name="$output_name" \
        --steps=100000 \
        --batch_size=8 \
        --num_workers=4 \
        --log_freq=200 \
        --save_checkpoint=true \
        --save_freq=20000 >"$log_path" 2>&1

    local exit_code=$?
    printf '%s\n' "$exit_code" >"$ROOT/${output_name}.exitcode"
    if [ "$exit_code" -eq 0 ]; then
        touch "$ROOT/${output_name}.done"
    fi
    return "$exit_code"
}

run_training green bottle_cap_green_merged_v1 || exit $?
run_training white bottle_cap_white_merged_v1
exit $?
