from lerobot.robots.utils import ensure_safe_goal_position


def test_ensure_safe_goal_position_accepts_integer_limit():
    goal_present_pos = {"joint": (10.0, 0.0)}

    assert ensure_safe_goal_position(goal_present_pos, 5) == {"joint": 5.0}
