#!/usr/bin/env python
# -*- coding: utf-8 -*-
import os
import hashlib
import time
from threading import Thread, Lock

import xbmc
import xbmcvfs

try:
    from xbmcvfs import translatePath
except ImportError:
    from xbmc import translatePath

BADGE_CACHE_DIR = None
_bg_queue = []
_bg_lock = Lock()
_bg_running = False
MAX_POSTER_HEIGHT = 600
PARALLEL_WORKERS = 4
EARLY_REFRESH_COUNT = 15


def _get_cache_dir():
    global BADGE_CACHE_DIR
    if BADGE_CACHE_DIR is None:
        BADGE_CACHE_DIR = translatePath('special://temp/pay_badges/')
        os.makedirs(BADGE_CACHE_DIR, exist_ok=True)
    return BADGE_CACHE_DIR


def hex_to_rgb(hex_color):
    h = hex_color.lstrip('#').lstrip('0x')
    if len(h) == 8:
        h = h[2:]
    if len(h) != 6:
        return (255, 102, 0)
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


def _cache_path_for(original_url, badge_mode, badge_text, border_color):
    cache_key = hashlib.md5(
        f"{original_url}|{badge_mode}|{badge_text}|{border_color}|v2".encode()
    ).hexdigest()
    return os.path.join(_get_cache_dir(), f"{cache_key}.jpg")


def get_badged_poster(original_url, badge_mode='both', border_color=(255, 102, 0),
                      badge_text='\u20AC', badge_bg_color=None):
    """Returns cached badge path if available, otherwise queues background
    processing and returns original URL (non-blocking)."""
    if not original_url:
        return original_url

    cached_path = _cache_path_for(original_url, badge_mode, badge_text, border_color)

    if os.path.exists(cached_path):
        return cached_path

    if badge_bg_color is None:
        badge_bg_color = border_color + (220,)
    _enqueue(original_url, badge_mode, border_color, badge_text, badge_bg_color, cached_path)
    return original_url


def _enqueue(original_url, badge_mode, border_color, badge_text, badge_bg_color, cached_path):
    global _bg_running
    with _bg_lock:
        _bg_queue.append((original_url, badge_mode, border_color, badge_text, badge_bg_color, cached_path))
        if not _bg_running:
            _bg_running = True
            t = Thread(target=_process_queue, daemon=True)
            t.start()


def _process_single(job):
    """Process a single badge job. Returns True if a new badge was created."""
    original_url, badge_mode, border_color, badge_text, badge_bg_color, cached_path = job
    if os.path.exists(cached_path):
        return False
    try:
        from PIL import Image, ImageDraw
        img = _load_image(original_url)
        if img is None:
            return False
        if img.height > MAX_POSTER_HEIGHT:
            ratio = MAX_POSTER_HEIGHT / img.height
            img = img.resize((int(img.width * ratio), MAX_POSTER_HEIGHT), Image.LANCZOS)
        img = img.convert('RGB')
        if badge_mode in ('border', 'both'):
            img = _draw_border(img, border_color, width=max(3, img.width // 60))
        if badge_mode in ('badge', 'both'):
            img = _draw_corner_badge(img, badge_text, badge_bg_color)
        img.save(cached_path, 'JPEG', quality=85)
        xbmc.log(f'[pay_badge] Cached: {os.path.basename(cached_path)} ({os.path.getsize(cached_path)//1024}KB)', xbmc.LOGINFO)
        return True
    except Exception as e:
        xbmc.log(f'[pay_badge] BG error: {e}', xbmc.LOGWARNING)
        return False


def _process_batch(jobs):
    """Process jobs in parallel (PARALLEL_WORKERS at a time). Returns new badge count."""
    if not jobs:
        return 0
    results = [False] * len(jobs)

    def _worker(index, job):
        results[index] = _process_single(job)

    for chunk_start in range(0, len(jobs), PARALLEL_WORKERS):
        chunk = jobs[chunk_start:chunk_start + PARALLEL_WORKERS]
        threads = []
        for i, job in enumerate(chunk):
            t = Thread(target=_worker, args=(chunk_start + i, job))
            threads.append(t)
            t.start()
        for t in threads:
            t.join(timeout=20)

    return sum(1 for r in results if r)


def _try_refresh(count):
    """Fire Container.Refresh if badge_auto_refresh is enabled."""
    try:
        from .common import Settings
        if Settings().badge_auto_refresh:
            time.sleep(0.5)
            xbmc.log(f'[pay_badge] {count} badges cached, refreshing view', xbmc.LOGINFO)
            xbmc.executebuiltin('Container.Refresh')
    except Exception as e:
        xbmc.log(f'[pay_badge] Refresh failed: {e}', xbmc.LOGWARNING)


def _process_queue():
    """Drain queue in two phases: early refresh after first screen, then cache the rest."""
    global _bg_running

    while True:
        with _bg_lock:
            if not _bg_queue:
                _bg_running = False
                return
            jobs = list(_bg_queue)
            _bg_queue.clear()

        first_batch = jobs[:EARLY_REFRESH_COUNT]
        rest_batch = jobs[EARLY_REFRESH_COUNT:]

        first_count = _process_batch(first_batch)

        if first_count > 0:
            _try_refresh(first_count)

        rest_count = _process_batch(rest_batch)
        total = first_count + rest_count
        if rest_count > 0:
            xbmc.log(f'[pay_badge] {total} total badges ({rest_count} cached after refresh)', xbmc.LOGINFO)


def _load_image(url_or_path):
    from PIL import Image
    import io

    if url_or_path.startswith('http'):
        try:
            import requests
            resp = requests.get(url_or_path, timeout=15)
            resp.raise_for_status()
            return Image.open(io.BytesIO(resp.content))
        except Exception as e:
            xbmc.log(f'[pay_badge] Download failed: {e}', xbmc.LOGWARNING)
            return None
    else:
        real_path = url_or_path
        if url_or_path.startswith('special://'):
            real_path = translatePath(url_or_path)
        if os.path.isfile(real_path):
            return Image.open(real_path)
    return None


def _draw_border(img, color, width=4):
    from PIL import Image
    bordered = Image.new('RGB', (img.width + 2 * width, img.height + 2 * width), color)
    bordered.paste(img, (width, width))
    return bordered


def _draw_corner_badge(img, text, bg_color):
    from PIL import ImageDraw

    draw = ImageDraw.Draw(img)
    badge_h = max(img.height // 8, 22)
    badge_w = max(img.width // 3, 36)
    x0 = img.width - badge_w

    bg_rgb = bg_color[:3] if len(bg_color) >= 3 else (255, 102, 0)
    draw.rectangle([x0, 0, img.width, badge_h], fill=bg_rgb)

    font_size = badge_h - 6
    font = _get_font(font_size)
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = x0 + (badge_w - tw) // 2
    ty = (badge_h - th) // 2
    draw.text((tx, ty), text, fill=(255, 255, 255), font=font)
    return img


_font_cache = {}


def _get_font(size):
    from PIL import ImageFont
    if size in _font_cache:
        return _font_cache[size]
    for fp in ['/system/fonts/Roboto-Bold.ttf', '/system/fonts/DroidSans-Bold.ttf',
               '/system/fonts/DroidSans.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf']:
        if os.path.isfile(fp):
            try:
                font = ImageFont.truetype(fp, size)
                _font_cache[size] = font
                return font
            except Exception:
                continue
    font = ImageFont.load_default()
    _font_cache[size] = font
    return font


def clear_cache():
    cache_dir = _get_cache_dir()
    try:
        for f in os.listdir(cache_dir):
            fp = os.path.join(cache_dir, f)
            if os.path.isfile(fp):
                os.remove(fp)
    except Exception:
        pass
