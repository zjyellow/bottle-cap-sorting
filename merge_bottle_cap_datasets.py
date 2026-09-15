import argparse
import copy
import json
import shutil
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq


WORKSPACE = Path(__file__).resolve().parent
DATASETS = WORKSPACE / "outputs" / "datasets"

parser = argparse.ArgumentParser(description="Merge selected prefixes of LeRobot datasets.")
parser.add_argument(
    "--source",
    action="append",
    required=True,
    metavar="NAME:COUNT",
    help="Source dataset directory name and number of episodes to take. Repeat for each source.",
)
parser.add_argument("--target", required=True, help="New dataset directory name.")
parser.add_argument("--task", required=True, help="Task label for every merged episode.")
args = parser.parse_args()


def parse_source(value: str) -> tuple[Path, range]:
    name, count_text = value.rsplit(":", 1)
    count = int(count_text)
    if not name or count <= 0:
        raise ValueError(f"Invalid --source value: {value}")
    return DATASETS / name, range(count)


SOURCES = [parse_source(value) for value in args.source]
TARGET = DATASETS / args.target
TEMP_TARGET = DATASETS / f"{args.target}.tmp_merge"
TASK = args.task.strip()
if not TASK:
    raise ValueError("--task cannot be empty")


def read_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def read_jsonl(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as file:
        return [json.loads(line) for line in file if line.strip()]


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as file:
        json.dump(value, file, indent=4, ensure_ascii=False)
        file.write("\n")


def write_jsonl(path: Path, values: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as file:
        for value in values:
            file.write(json.dumps(value, ensure_ascii=False) + "\n")


if TARGET.exists() or TEMP_TARGET.exists():
    raise FileExistsError(f"Merge target already exists: {TARGET} or {TEMP_TARGET}")

source_metadata = []
for source_root, selected_episodes in SOURCES:
    info = read_json(source_root / "meta" / "info.json")
    episodes = {item["episode_index"]: item for item in read_jsonl(source_root / "meta" / "episodes.jsonl")}
    stats = {
        item["episode_index"]: item
        for item in read_jsonl(source_root / "meta" / "episodes_stats.jsonl")
    }
    selected_episodes = list(selected_episodes)
    missing = [episode for episode in selected_episodes if episode not in episodes or episode not in stats]
    if missing:
        raise ValueError(f"Missing metadata in {source_root}: {missing}")
    source_metadata.append((source_root, selected_episodes, info, episodes, stats))

reference_info = source_metadata[0][2]
for source_root, _, info, _, _ in source_metadata[1:]:
    for field in ("codebase_version", "robot_type", "fps", "features", "chunks_size"):
        if info[field] != reference_info[field]:
            raise ValueError(f"Incompatible {field} in {source_root}")

TEMP_TARGET.mkdir(parents=True)
merged_episodes = []
merged_stats = []
global_frame_index = 0
new_episode_index = 0
video_keys = [
    key for key, feature in reference_info["features"].items() if feature["dtype"] == "video"
]
chunks_size = reference_info["chunks_size"]

for source_root, selected_episodes, info, episodes, stats in source_metadata:
    for old_episode_index in selected_episodes:
        old_chunk = old_episode_index // chunks_size
        new_chunk = new_episode_index // chunks_size
        source_data = source_root / info["data_path"].format(
            episode_chunk=old_chunk,
            episode_index=old_episode_index,
        )
        table = pq.read_table(source_data)
        episode_length = table.num_rows
        if episode_length != episodes[old_episode_index]["length"]:
            raise ValueError(f"Frame count mismatch in {source_data}")

        episode_column = pa.array([new_episode_index] * episode_length, type=pa.int64())
        index_column = pa.array(
            range(global_frame_index, global_frame_index + episode_length), type=pa.int64()
        )
        task_column = pa.array([0] * episode_length, type=pa.int64())
        table = table.set_column(table.schema.get_field_index("episode_index"), "episode_index", episode_column)
        table = table.set_column(table.schema.get_field_index("index"), "index", index_column)
        table = table.set_column(table.schema.get_field_index("task_index"), "task_index", task_column)

        target_data = TEMP_TARGET / reference_info["data_path"].format(
            episode_chunk=new_chunk,
            episode_index=new_episode_index,
        )
        target_data.parent.mkdir(parents=True, exist_ok=True)
        pq.write_table(table, target_data, compression="zstd")

        for video_key in video_keys:
            source_video = source_root / info["video_path"].format(
                episode_chunk=old_chunk,
                video_key=video_key,
                episode_index=old_episode_index,
            )
            target_video = TEMP_TARGET / reference_info["video_path"].format(
                episode_chunk=new_chunk,
                video_key=video_key,
                episode_index=new_episode_index,
            )
            if not source_video.is_file():
                raise FileNotFoundError(source_video)
            target_video.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_video, target_video)

        merged_episodes.append(
            {"episode_index": new_episode_index, "tasks": [TASK], "length": episode_length}
        )
        episode_stats = copy.deepcopy(stats[old_episode_index])
        episode_stats["episode_index"] = new_episode_index
        scalar_stats = episode_stats["stats"]
        scalar_stats["episode_index"].update(
            {"min": [new_episode_index], "max": [new_episode_index], "mean": [float(new_episode_index)]}
        )
        old_index_min = scalar_stats["index"]["min"][0]
        index_shift = global_frame_index - old_index_min
        for field in ("min", "max", "mean"):
            scalar_stats["index"][field][0] += index_shift
        scalar_stats["task_index"].update({"min": [0], "max": [0], "mean": [0.0]})
        merged_stats.append(episode_stats)

        global_frame_index += episode_length
        new_episode_index += 1

merged_info = copy.deepcopy(reference_info)
merged_info.update(
    {
        "total_episodes": new_episode_index,
        "total_frames": global_frame_index,
        "total_tasks": 1,
        "total_videos": new_episode_index * len(video_keys),
        "total_chunks": (new_episode_index + chunks_size - 1) // chunks_size,
        "splits": {"train": f"0:{new_episode_index}"},
    }
)

write_json(TEMP_TARGET / "meta" / "info.json", merged_info)
write_jsonl(TEMP_TARGET / "meta" / "episodes.jsonl", merged_episodes)
write_jsonl(TEMP_TARGET / "meta" / "episodes_stats.jsonl", merged_stats)
write_jsonl(TEMP_TARGET / "meta" / "tasks.jsonl", [{"task_index": 0, "task": TASK}])

TEMP_TARGET.rename(TARGET)
print(f"Merged dataset: {TARGET}")
print(f"Episodes: {new_episode_index}")
print(f"Frames: {global_frame_index}")
print(f"Videos: {new_episode_index * len(video_keys)}")
