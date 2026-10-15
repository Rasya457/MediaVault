from unittest.mock import MagicMock, patch

import pytest

from app.services import spotify
from app.services.spotify import (
    SpotifyTrack,
    SpotifyUnsupportedError,
    is_spotify_url,
    parse_track_id,
    search_query,
)


def test_is_spotify_url():
    assert is_spotify_url("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQ")
    assert not is_spotify_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ")


def test_parse_track_id():
    assert parse_track_id("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQ") == "4uLU6hMCjMI75M1A2tKUQ"
    assert (
        parse_track_id("https://open.spotify.com/intl-id/track/4uLU6hMCjMI75M1A2tKUQ?si=abc")
        == "4uLU6hMCjMI75M1A2tKUQ"
    )


def test_parse_rejects_non_track():
    with pytest.raises(SpotifyUnsupportedError):
        parse_track_id("https://open.spotify.com/album/1ABC")
    with pytest.raises(SpotifyUnsupportedError):
        parse_track_id("https://open.spotify.com/playlist/2DEF")
    with pytest.raises(SpotifyUnsupportedError):
        parse_track_id("https://open.spotify.com/episode/3GHI")


def test_get_track_maps_metadata():
    fake = MagicMock()
    fake.track.return_value = {
        "name": "Judul Lagu",
        "artists": [{"name": "Artis A"}, {"name": "Artis B"}],
        "album": {"name": "Album X", "images": [{"url": "https://cover/img.jpg"}]},
        "duration_ms": 210000,
    }
    with patch.object(spotify, "_client", return_value=fake):
        track = spotify.get_track("https://open.spotify.com/track/ID123")
    assert track.id == "ID123"
    assert track.title == "Judul Lagu"
    assert track.artists == "Artis A, Artis B"
    assert track.album == "Album X"
    assert track.cover == "https://cover/img.jpg"
    assert track.duration_sec == 210
    assert track.spotify_url == "https://open.spotify.com/track/ID123"


def test_search_query():
    track = SpotifyTrack(
        id="ID123", title="Judul", artists="Artis", album="",
        cover=None, duration_sec=None, spotify_url="https://open.spotify.com/track/ID123",
    )
    assert search_query(track) == "Artis - Judul"
