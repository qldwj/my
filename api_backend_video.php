<?php
/**
 * 视频分享播放页（单文件）
 *
 * 播放引擎直接采用开源项目 p2p_mp4（HTTP + WebTorrent P2P 混合播放）：
 *   https://github.com/wietrade/p2p_mp4/
 * 本项目为多文件（pear-player.js / webtorrent.min.js ...），
 * 这里做成「只需要部署一个文件」：播放器内核从公开 CDN 加载，其余全部内联在本文件里。
 *
 * 部署：放到站点根目录，使其可通过 https://qlyyz.xyz/video 访问
 *       根目录保存为 video.php + 伪静态 rewrite：
 *         Nginx : location = /video { rewrite ^ /video.php last; }
 *         Apache: RewriteRule ^video$ video.php [L]
 *       （也可直接用 https://qlyyz.xyz/video.php?url=... ）
 *
 * 用法：https://qlyyz.xyz/video?url=<密文>[&t=标题][&torrent=种子直链][&magnet=磁力][&tracker=tracker]
 *
 * 密文生成（App 端 lib/utils/video_share_codec.dart）：
 *   1. 原始视频地址 gzdeflate($str, 9)  → 最高级别 raw DEFLATE 压缩
 *   2. Base32 编码（A-Z2-7，去掉 '=' 填充）→ 只有大写字母和数字，无特殊字符
 *
 * 本页解密（与上面一一对应）：
 *   1. Base32 解码还原二进制压缩字节
 *   2. gzinflate() 解压得到原始视频地址
 *   3. 交给 p2p_mp4 的 PearPlayer 播放，并支持再次分享给好友
 */

declare(strict_types=1);

// 是否允许直接用明文 http(s) 地址播放（调试方便；不想暴露可改为 false）
const VIDEO_SHARE_ALLOW_PLAIN_URL = true;

// p2p_mp4 后端（视频注册 / 统计 / tracker 下发）
const P2P_BACKEND = 'https://bot3.1230sb.com/p2p_mp4';
// p2p_mp4 播放器内核 CDN（公开可访问）
const P2P_PLAYER_CDN = 'https://wietrade.github.io/p2p_mp4';

/** RFC4648 Base32 解码（大小写均可，忽略 '=' 填充与非法字符） */
function video_share_base32_decode(string $input): string
{
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    $input = strtoupper(preg_replace('/[^A-Za-z2-7]/', '', $input) ?? '');
    $output = '';
    $buffer = 0;
    $bits = 0;
    $length = strlen($input);
    for ($i = 0; $i < $length; $i++) {
        $index = strpos($alphabet, $input[$i]);
        if ($index === false) {
            continue;
        }
        $buffer = ($buffer << 5) | $index;
        $bits += 5;
        if ($bits >= 8) {
            $bits -= 8;
            $output .= chr(($buffer >> $bits) & 0xFF);
        }
    }
    return $output;
}

/** 解密分享参数：Base32 解码 → gzinflate → 原始视频地址；失败返回 null */
function video_share_decode(string $encoded): ?string
{
    $encoded = trim($encoded);
    if ($encoded === '') {
        return null;
    }
    // 调试用：明文直链
    if (VIDEO_SHARE_ALLOW_PLAIN_URL && preg_match('#^https?://#i', $encoded)) {
        return video_share_normalize($encoded);
    }
    $binary = video_share_base32_decode($encoded);
    if ($binary === '') {
        return null;
    }
    // gzinflate 对损坏数据会抛 warning，这里静默处理
    $plain = @gzinflate($binary);
    if (!is_string($plain) || $plain === '') {
        return null;
    }
    return video_share_normalize($plain);
}

/** 校验并规范化视频地址，只允许 http(s) */
function video_share_normalize(string $url): ?string
{
    $url = trim($url);
    if (!preg_match('#^https?://#i', $url)) {
        return null;
    }
    // 去掉地址末尾可能被带上的引号/空白
    return rtrim($url, " \t\n\r\0\x0B\"'");
}

/** 转义输出 */
function video_share_h(?string $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

$rawUrl = (string) ($_GET['url'] ?? '');
$videoUrl = video_share_decode($rawUrl);

$rawTitle = trim((string) ($_GET['t'] ?? ''));
$pageTitle = $rawTitle !== '' ? $rawTitle : '视频分享';

if ($videoUrl === null) {
    http_response_code(400);
    header('Content-Type: text/html; charset=utf-8');
    ?>
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>链接无效</title>
        <style>
            body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
                   background: #101114; color: #e6e6e6; font: 15px/1.7 system-ui, -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif; }
            .box { max-width: 420px; padding: 32px; text-align: center; }
            h1 { font-size: 20px; margin: 0 0 12px; }
            p { margin: 0; color: #9aa0a6; }
        </style>
    </head>
    <body>
    <div class="box">
        <h1>分享链接无效或已损坏</h1>
        <p>请让分享者重新发送链接。</p>
    </div>
    </body>
    </html>
    <?php
    exit;
}

// 可选参数：种子 / 磁力 / tracker（有种子才会启用 P2P，否则纯 HTTP 播放）
$optTorrent = trim((string) ($_GET['torrent'] ?? ''));
$optMagnet = trim((string) ($_GET['magnet'] ?? ''));
$optTracker = trim((string) ($_GET['tracker'] ?? ''));

header('Content-Type: text/html; charset=utf-8');
header('Referrer-Policy: no-referrer');
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="referrer" content="no-referrer">
    <title><?= video_share_h($pageTitle) ?></title>
    <style>
        :root { color-scheme: dark; }
        * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
        html, body { margin: 0; height: 100%; background: #0b0c0f; color: #e8e8e8;
                     font: 14px/1.6 system-ui, -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
                     overflow: hidden; }
        .wrap { display: flex; flex-direction: column; height: 100%; }
        .bar { display: flex; align-items: center; gap: 10px; padding: 10px 14px; flex: none;
               background: #14161b; border-bottom: 1px solid #23262e; }
        .bar h1 { flex: 1; margin: 0; font-size: 15px; font-weight: 600;
                  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .btn { flex: none; display: inline-flex; align-items: center; gap: 6px;
               padding: 7px 14px; border: 0; border-radius: 999px; cursor: pointer;
               background: #2b6cff; color: #fff; font-size: 13px; font-weight: 600; }
        .btn:active { transform: scale(.97); }
        .btn.ghost { background: #23262e; color: #c9ced6; }
        .stage { flex: 1; min-height: 0; position: relative; background: #000; display: flex;
                 align-items: center; justify-content: center; }
        video { width: 100%; height: 100%; background: #000; outline: none; }
        .overlay { position: absolute; inset: 0; display: flex; flex-direction: column;
                   align-items: center; justify-content: center; gap: 10px; text-align: center;
                   padding: 24px; background: rgba(8,9,12,.92); }
        .overlay[hidden] { display: none; }
        .spinner { width: 34px; height: 34px; border: 3px solid #2a2f3a; border-top-color: #2b6cff;
                   border-radius: 50%; animation: spin .8s linear infinite; }
        @keyframes spin { to { transform: rotate(360deg); } }
        .tip { color: #8b909a; font-size: 12.5px; max-width: 340px; }
        .stat { color: #79c0ff; font-size: 12px; }
        .stat b { color: #7ee787; font-family: Consolas, monospace; }
        .toast { position: fixed; left: 50%; bottom: 42px; transform: translateX(-50%);
                 background: rgba(20,22,27,.96); border: 1px solid #2c313b; color: #e8e8e8;
                 padding: 10px 18px; border-radius: 999px; font-size: 13px; opacity: 0;
                 pointer-events: none; transition: opacity .25s; z-index: 9; }
        .toast.show { opacity: 1; }
    </style>
</head>
<body>
<div class="wrap">
    <div class="bar">
        <h1><?= video_share_h($pageTitle) ?></h1>
        <button class="btn ghost" id="btn-open" type="button">原片</button>
        <button class="btn" id="btn-share" type="button">分享</button>
    </div>
    <div class="stage">
        <video id="player" controls autoplay playsinline preload="metadata"></video>
        <div class="overlay" id="overlay">
            <div class="spinner" id="spinner"></div>
            <div class="stat" id="stat">正在连接 P2P 加速…</div>
            <div class="tip" id="tip">播放器内核由开源项目 p2p_mp4 提供（HTTP + P2P 混合加速）</div>
        </div>
    </div>
</div>
<div class="toast" id="toast"></div>

<script>
    // ===== 页面参数（PHP 已解密）=====
    window.__VIDEO__ = {
        url: <?= json_encode($videoUrl, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>,
        torrent: <?= json_encode($optTorrent, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>,
        magnet: <?= json_encode($optMagnet, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>,
        tracker: <?= json_encode($optTracker, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>,
        // 原样保留本页分享参数，方便“再次分享”
        shareLink: location.href
    };
</script>

<script>
    // ===== p2p_mp4 播放器配置（必须在 pear-player.js 之前）=====
    window.PEAR_BACKEND = '<?= P2P_BACKEND ?>';
    window.PearConfig = {
        getNodesUrl: window.PEAR_BACKEND + '/v1/customer/nodes',
        signalWsUrl: null,                    // 外网 P2P 走 WebTorrent wss tracker 信令
        statdUrl: window.PEAR_BACKEND
    };
    // 动态拉取 WebRTC rtcConfig（多 STUN/TURN），失败则用播放器内置默认
    fetch(window.PEAR_BACKEND + '/rtc_config')
        .then(function (r) { return r.json(); })
        .then(function (d) {
            if (d && d.rtcConfig && d.rtcConfig.iceServers && d.rtcConfig.iceServers.length) {
                window.PearConfig.rtcConfig = d.rtcConfig;
            }
        })
        .catch(function () {});
</script>

<!-- p2p_mp4 播放器内核（单文件方案的唯一外部依赖） -->
<script src="<?= P2P_PLAYER_CDN ?>/pear-player.js"></script>

<script>
(function () {
    'use strict';

    var conf = window.__VIDEO__;
    var videoEl = document.getElementById('player');
    var overlay = document.getElementById('overlay');
    var statEl = document.getElementById('stat');
    var tipEl = document.getElementById('tip');
    var spinner = document.getElementById('spinner');

    var player = null;
    var httpBytes = 0, p2pBytes = 0;

    function toast(msg) {
        var el = document.getElementById('toast');
        el.textContent = msg;
        el.classList.add('show');
        setTimeout(function () { el.classList.remove('show'); }, 1800);
    }

    function hideOverlay() { overlay.hidden = true; }
    function fail(msg) {
        spinner.style.display = 'none';
        statEl.textContent = '播放失败';
        tipEl.textContent = msg;
    }

    function renderStat() {
        var total = httpBytes + p2pBytes;
        if (!total) { statEl.textContent = '正在连接 P2P 加速…'; return; }
        var p2pRate = (p2pBytes / total * 100).toFixed(0);
        statEl.innerHTML = 'P2P 加速中 · 已取 ' + (total / 1048576).toFixed(1) +
            'MB · P2P 占 <b>' + p2pRate + '%</b>';
    }

    // ===== 分享（再次分享给好友）=====
    document.getElementById('btn-share').addEventListener('click', function () {
        var link = conf.shareLink;
        var title = document.title || '视频分享';
        if (navigator.share) {
            navigator.share({ title: title, url: link }).catch(function () {
                copy(link);
            });
            return;
        }
        copy(link);
    });

    function copy(text) {
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(function () {
                toast('分享链接已复制，可发给好友');
            }).catch(function () { fallbackCopy(text); });
        } else {
            fallbackCopy(text);
        }
    }

    function fallbackCopy(text) {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.opacity = '0';
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); toast('分享链接已复制，可发给好友'); }
        catch (e) { toast('复制失败，请长按地址栏复制'); }
        document.body.removeChild(ta);
    }

    document.getElementById('btn-open').addEventListener('click', function () {
        window.open(conf.url, '_blank', 'noopener');
    });

    // ===== 注册视频 + 启动播放器 =====
    var playerMagnet = conf.magnet || null;
    var playerTorrentUrl = conf.torrent || null;
    var playerTrackers = null;
    var infoHash = '';

    var TRACKERS_FALLBACK = ['wss://bot3.1230sb.com/tracker', 'wss://tracker.openwebtorrent.com'];

    function startPlayer() {
        if (!window.PearPlayer || !PearPlayer.isMSESupported()) {
            // 浏览器不支持 MSE：直接原生播放
            videoEl.src = conf.url;
            videoEl.play().catch(function () {});
            hideOverlay();
            return;
        }

        player = new PearPlayer('#player', {
            scheduler: 'IdleFirst',
            autoplay: true,
            interval: 5000,
            useDataChannel: false,        // 外网走 WebTorrent（不连本机 WS）
            dataChannels: 10,
            useTorrent: !!playerMagnet,   // 有种子才启用 P2P，否则纯 HTTP
            trackers: playerTrackers,
            magnetURI: playerMagnet,
            torrentUrl: playerTorrentUrl,
            useMonitor: true,
            debug: false,
            algorithm: 'pull',
            geoEnabled: false
        });

        player.on('begin', function (fileLength, chunks) {
            hideOverlay();
        });
        player.on('canplay', function () { hideOverlay(); });
        player.on('traffic', function (mac, size, type) {
            if (type === 'WebRTC_Browser') { p2pBytes += size; }
            else if (type === 'HTTP_Server' || type === 'HTTP_Node') { httpBytes += size; }
            renderStat();
        });
        player.on('peercount', function (n) {
            if (typeof n === 'number' && n > 0) {
                tipEl.textContent = 'P2P 已连接 ' + n + ' 位用户，人越多越快';
            }
        });
        player.on('fallback', function () {
            // 播放器降级：直接用 HTTP 源播放
            if (!videoEl.src) {
                videoEl.src = conf.url;
                videoEl.play().catch(function () {});
            }
            hideOverlay();
        });
        player.on('exception', function () {
            if (!videoEl.src) { videoEl.src = conf.url; }
            hideOverlay();
        });

        // 兜底：3 秒还没画面就先挂上直链源，保证一定能播
        setTimeout(function () {
            if (overlay.hidden) return;
            if (!videoEl.src) {
                videoEl.src = conf.url;
                videoEl.play().catch(function () {});
            }
            hideOverlay();
        }, 3500);
    }

    function boot() {
        // 先用直链保证「一定能播放」，再让播放器接管做 P2P 加速
        videoEl.src = conf.url;

        if (!conf.url) { fail('分享链接缺少视频地址'); return; }

        fetch(window.PEAR_BACKEND + '/v1/videos?url=' + encodeURIComponent(conf.url))
            .then(function (r) {
                if (r.status === 404) {
                    // 未注册 → 自动注册（带种子/磁力则启用 P2P）
                    return fetch(window.PEAR_BACKEND + '/v1/videos', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            url: conf.url,
                            magnet: conf.magnet || null,
                            torrentUrl: conf.torrent || null
                        })
                    }).then(function (r2) { return r2.json(); });
                }
                return r.json();
            })
            .then(function (data) {
                if (data && data.video) {
                    var v = data.video;
                    playerMagnet = v.magnetURI || playerMagnet;
                    playerTorrentUrl = v.torrentUrl || playerTorrentUrl;
                    infoHash = v.infoHash || '';
                    var apiTrackers = (v.trackers && v.trackers.length)
                        ? v.trackers
                        : (conf.tracker ? conf.tracker.split(',').filter(function (t) { return t; }) : []);
                    playerTrackers = [];
                    var seen = {};
                    apiTrackers.concat(TRACKERS_FALLBACK).forEach(function (t) {
                        if (t && !seen[t]) { seen[t] = true; playerTrackers.push(t); }
                    });
                    if (v.localFile) { videoEl.src = window.PEAR_BACKEND + '/' + v.rel; }
                }
                startPlayer();
            })
            .catch(function () {
                // 注册失败（后端不可用）→ 纯 HTTP 播放，不影响观看
                startPlayer();
            });
    }

    boot();
})();
</script>
</body>
</html>
