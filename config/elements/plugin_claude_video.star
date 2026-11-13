# 手段: Claude Code のプラグイン claude-video の /watch が、動画を取得してフレームを抜くための yt-dlp と ffmpeg。
# プラグインを外したら、この要素も claude_code の requires から外す。
def user_config():
    return {"home": {"home.packages": [pkg("yt-dlp"), pkg("ffmpeg")]}}
