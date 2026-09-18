<?php
/**
 * 视频分享播放页（单文件，PHP）
 *
 * 部署：把本文件放到站点根目录，使其可通过 https://qlyyz.xyz/video 访问，
 *       例如：根目录保存为 video.php + 伪静态 rewrite
 *         Nginx : location = /video { rewrite ^ /video.php last; }
 *         Apache: RewriteRule ^video$ video.php [L]
 *       （也可以直接用 https://qlyyz.xyz/video.php?url=... ）
 *
 * 用法：https://qlyyz.xyz/video?url=<密文>[&t=标题][&torrent=种子直链][&magnet=磁力]
 *
 * 密文生成（App 端 lib/utils/video_share_codec.dart）：
 *   1. 原始视频地址 gzdeflate($str, 9)  → 最高级别 raw DEFLATE 压缩
 *   2. Base32 编码（A-Z2-7，去掉 '=' 填充）→ 只有大写字母和数字，无特殊字符
 *
 * 本页解密（与上面一一对应）：
 *   1. Base32 解码还原二进制压缩字节
 *   2. gzinflate() 解压得到原始视频地址
 *   3. 交给开源项目 p2p_mp4（HTTP + WebTorrent P2P 混合播放）播放
 */

declare(strict_types=1);

// 是否允许直接用明文 http(s) 地址播放（调试方便；不想暴露可改为 false）
const VIDEO_SHARE_ALLOW_PLAIN_URL = true;

// p2p_mp4 播放器地址（开源项目：https://github.com/wietrade/p2p_mp4/）
const VIDEO_SHARE_PLAYER = 'https://bot3.1230sb.com/p2p_mp4/';

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

/** 简单转义输出 */
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

// 组装 p2p_mp4 播放地址：核心只依赖 url，种子/磁力可选（有种子才会启用 P2P）
$playerUrl = VIDEO_SHARE_PLAYER . '?url=' . rawurlencode($videoUrl);
foreach (['torrent', 'magnet', 'tracker'] as $extra) {
    $value = trim((string) ($_GET[$extra] ?? ''));
    if ($value !== '') {
        $playerUrl .= '&' . $extra . '=' . rawurlencode($value);
    }
}

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
        * { box-sizing: border-box; }
        html, body { margin: 0; height: 100%; background: #0f1013; color: #e8e8e8;
                     font: 14px/1.6 system-ui, -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif; }
        .wrap { display: flex; flex-direction: column; height: 100%; }
        .bar { display: flex; align-items: center; gap: 12px; padding: 10px 14px;
               background: #17181d; border-bottom: 1px solid #24262d; }
        .bar h1 { flex: 1; margin: 0; font-size: 15px; font-weight: 600;
                  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .bar a { color: #7cb2ff; text-decoration: none; font-size: 13px; white-space: nowrap; }
        .stage { flex: 1; min-height: 0; position: relative; background: #000; }
        .stage iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
        .tip { padding: 8px 14px; font-size: 12px; color: #8b909a; background: #14151a; }
        @media (max-width: 600px) {
            .bar { padding: 8px 10px; }
            .tip { display: none; }
        }
    </style>
</head>
<body>
<div class="wrap">
    <div class="bar">
        <h1><?= video_share_h($pageTitle) ?></h1>
        <a href="<?= video_share_h($playerUrl) ?>" target="_blank" rel="noreferrer noopener">在新窗口打开</a>
    </div>
    <div class="stage">
        <iframe
            src="<?= video_share_h($playerUrl) ?>"
            allow="autoplay; fullscreen; encrypted-media; picture-in-picture; clipboard-write"
            allowfullscreen
            referrerpolicy="no-referrer"
            title="<?= video_share_h($pageTitle) ?>"></iframe>
    </div>
    <div class="tip">播放器由开源项目 p2p_mp4 提供（HTTP + P2P 混合加速）</div>
</div>
</body>
</html>
