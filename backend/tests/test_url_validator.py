from app.utils.url_validator import is_allowed_url


def test_youtube_allowed():
    assert is_allowed_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ")


def test_short_link_allowed():
    assert is_allowed_url("https://youtu.be/dQw4w9WgXcQ")


def test_tiktok_allowed():
    assert is_allowed_url("https://www.tiktok.com/@user/video/123")


def test_random_host_rejected():
    assert not is_allowed_url("https://example.com/video.mp4")


def test_localhost_rejected():
    assert not is_allowed_url("http://localhost:8000/admin")


def test_private_ip_rejected():
    assert not is_allowed_url("http://192.168.1.10/video.mp4")
    assert not is_allowed_url("http://127.0.0.1/x")


def test_non_http_rejected():
    assert not is_allowed_url("ftp://www.youtube.com/x")
    assert not is_allowed_url("file:///etc/passwd")
