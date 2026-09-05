<?php
/**
 * 樱花动漫 自建评论接口
 *
 * 功能：发表/查看评论、回复、点赞、管理员下架、关键词+网址拦截
 * 来源：source='server'（本服务器评论）
 *
 * 接口：
 *   POST ?action=add     body: {"subjectId":1,"episode":0,"text":"评论","sender":"昵称","rating":8,"uid":"1234567","avatar":"https://..."}
 *                         episode=0 表示条目评论，>0 表示剧集评论；rating 0-10（0=不评分）；uid/avatar 用于显示头像
 *   POST ?action=reply   body: {"commentId":1,"text":"回复","sender":"昵称"}
 *   GET  ?action=list    ?id=1&ep=0        → 评论列表（含回复，source=server）
 *   POST ?action=vote    body: {"id":1,"value":1}     → 点赞(1)/取消(0)
 *   POST ?action=remove  body: {"id":1,"admin_key":"..."}  → 管理员下架
 *   POST ?action=restore body: {"id":1,"admin_key":"..."}  → 恢复
 *
 * 部署：qlyyz.xyz/api/comment.php（data/comment.db 自动创建）
 */

header('Content-Type: application/json; charset=utf-8');

define('COMMENT_DIR', __DIR__ . '/data');
define('COMMENT_DB', COMMENT_DIR . '/comment.db');
// ⚠️ 部署后请修改
define('COMMENT_ADMIN_KEY', 'sakura_comment_admin_2026');

// MySQL 配置（用于验证用户身份）
$MYSQL_HOST = 'localhost';
$MYSQL_USER = 's7884487';
$MYSQL_PASS = 'dhLW27buZL';
$MYSQL_DB   = 's7884487';

/**
 * 验证用户 Token，返回用户信息或 null
 */
function verifyUser() {
    global $MYSQL_HOST, $MYSQL_USER, $MYSQL_PASS, $MYSQL_DB;
    
    $headers = [];
    if (function_exists('getallheaders')) {
        foreach (getallheaders() as $k => $v) $headers[strtolower($k)] = $v;
    } else {
        foreach ($_SERVER as $k => $v) {
            if (strpos($k, 'HTTP_') === 0) {
                $headers[strtolower(str_replace('_', '-', substr($k, 5)))] = $v;
            }
        }
    }
    
    $auth = $headers['authorization'] ?? '';
    if (!preg_match('/^Bearer\s+(.+)$/i', $auth, $m)) {
        return null;
    }
    $token = $m[1];
    
    try {
        $db = new mysqli($MYSQL_HOST, $MYSQL_USER, $MYSQL_PASS, $MYSQL_DB);
        if ($db->connect_error) return null;
        $db->set_charset('utf8mb4');
        $stmt = $db->prepare("SELECT id, email, nickname FROM users WHERE token = ?");
        $stmt->bind_param('s', $token);
        $stmt->execute();
        $user = $stmt->get_result()->fetch_assoc();
        $stmt->close(); $db->close();
        return $user;
    } catch (Exception $e) {
        return null;
    }
}

if (!is_dir(COMMENT_DIR)) @mkdir(COMMENT_DIR, 0777, true);
$db = new SQLite3(COMMENT_DB);
$db->exec("CREATE TABLE IF NOT EXISTS comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    subject_id INTEGER NOT NULL,
    episode INTEGER NOT NULL DEFAULT 0,
    parent_id INTEGER NOT NULL DEFAULT 0,
    text TEXT NOT NULL,
    sender TEXT DEFAULT '',
    uid TEXT DEFAULT '',
    avatar TEXT DEFAULT '',
    rating INTEGER DEFAULT 0,
    votes INTEGER DEFAULT 0,
    status TEXT DEFAULT 'active',
    source TEXT DEFAULT 'server',
    pinned INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL
)");
// 兼容旧表：补 pinned / rating / uid / avatar 列
try {
    $db->exec("ALTER TABLE comments ADD COLUMN pinned INTEGER DEFAULT 0");
} catch (Exception $e) {}
try {
    $db->exec("ALTER TABLE comments ADD COLUMN rating INTEGER DEFAULT 0");
} catch (Exception $e) {}
try {
    $db->exec("ALTER TABLE comments ADD COLUMN uid TEXT DEFAULT ''");
} catch (Exception $e) {}
try {
    $db->exec("ALTER TABLE comments ADD COLUMN avatar TEXT DEFAULT ''");
} catch (Exception $e) {}
$db->exec("CREATE INDEX IF NOT EXISTS idx_comment_lookup ON comments (subject_id, episode, status)");

/** 内置敏感词 */
$BUILTIN_KEYWORDS = [
    '妈的','傻逼','煞笔','草泥马','nmsl','cnm','习近平','敏感','翻墙','毒品','枪支','赌博','色情','裸聊','约炮','法轮','台独',
];

function readBody() {
    $raw = file_get_contents('php://input');
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

function containsUrl($text) {
    if (preg_match('#(https?://|www\.|\.(com|cn|net|org|tv|cc|top|xyz|io|me|info|biz|site|vip)([/\s]|$))#i', $text)) {
        return true;
    }
    if (preg_match('#\d{1,3}(\.\d{1,3}){3}#', $text)) return true;
    return false;
}

function matchKeyword($text, $db, $builtin) {
    foreach ($builtin as $kw) {
        if ($kw !== '' && mb_strpos($text, $kw) !== false) return $kw;
    }
    $res = $db->query("SELECT keyword FROM keywords");
    while ($row = $res->fetchArray(SQLITE3_ASSOC)) {
        if ($row['keyword'] !== '' && mb_strpos($text, $row['keyword']) !== false) return $row['keyword'];
    }
    return null;
}

$db->exec("CREATE TABLE IF NOT EXISTS keywords (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    keyword TEXT UNIQUE NOT NULL,
    created_at INTEGER NOT NULL
)");
$db->exec("CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
)");

$action = $_GET['action'] ?? '';

switch ($action) {
    case 'add': {
        // 🔒 验证用户身份
        $user = verifyUser();
        if (!$user) {
            echo json_encode(['success' => false, 'error' => '请先登录']); break;
        }
        
        $input = readBody();
        $subjectId = (int)($input['subjectId'] ?? 0);
        $episode = (int)($input['episode'] ?? 0);
        $text = trim((string)($input['text'] ?? ''));
        $sender = $user['nickname'] ?? $user['email'] ?? '匿名';
        $uid = (string)($user['id'] ?? '');
        $avatar = trim((string)($input['avatar'] ?? ''));
        $rating = (int)($input['rating'] ?? 0);
        if ($rating < 0) $rating = 0;
        if ($rating > 10) $rating = 10;
        if ($subjectId <= 0 || $text === '') {
            echo json_encode(['success' => false, 'error' => '参数无效']);
            break;
        }
        if (mb_strlen($text) > 500) {
            echo json_encode(['success' => false, 'error' => '评论过长']);
            break;
        }
        if (containsUrl($text)) {
            echo json_encode(['success' => false, 'error' => '评论不能包含网址']);
            break;
        }
        $hit = matchKeyword($text, $db, $BUILTIN_KEYWORDS);
        if ($hit !== null) {
            echo json_encode(['success' => false, 'error' => '内容包含敏感词，已被拦截']);
            break;
        }
        // 🔧 防重复提交：同一用户同一番剧 60 秒内相同内容不重复入库
        $dupKey = $uid !== '' ? $uid : $sender;
        if ($dupKey !== '') {
            $dup = $db->querySingle("SELECT COUNT(*) FROM comments WHERE subject_id = $subjectId AND episode = $episode
                AND text = '" . SQLite3::escapeString($text) . "' AND sender = '" . SQLite3::escapeString($dupKey) . "'
                AND created_at >= " . (time() - 60));
            if ($dup > 0) {
                echo json_encode(['success' => false, 'error' => '评论已提交，请勿重复发送']);
                break;
            }
        }
        $stmt = $db->prepare("INSERT INTO comments (subject_id, episode, parent_id, text, sender, uid, avatar, rating, status, source, created_at)
            VALUES (?, ?, 0, ?, ?, ?, ?, ?, 'active', 'server', ?)");
        $stmt->bindValue(1, $subjectId, SQLITE3_INTEGER);
        $stmt->bindValue(2, $episode, SQLITE3_INTEGER);
        $stmt->bindValue(3, $text, SQLITE3_TEXT);
        $stmt->bindValue(4, $sender, SQLITE3_TEXT);
        $stmt->bindValue(5, $uid, SQLITE3_TEXT);
        $stmt->bindValue(6, $avatar, SQLITE3_TEXT);
        $stmt->bindValue(7, $rating, SQLITE3_INTEGER);
        $stmt->bindValue(8, time(), SQLITE3_INTEGER);
        $stmt->execute();
        echo json_encode(['success' => true, 'id' => $db->lastInsertRowID(), 'message' => '评论已发布']);
        break;
    }

    case 'reply': {
        // 🔒 验证用户身份
        $user = verifyUser();
        if (!$user) {
            echo json_encode(['success' => false, 'error' => '请先登录']); break;
        }
        
        $input = readBody();
        $commentId = (int)($input['commentId'] ?? 0);
        $text = trim((string)($input['text'] ?? ''));
        $sender = $user['nickname'] ?? $user['email'] ?? '匿名';
        $parent = $db->querySingle("SELECT subject_id, episode, source FROM comments WHERE id = " . $commentId, true);
        if (!$parent || $text === '') {
            echo json_encode(['success' => false, 'error' => '参数无效']);
            break;
        }
        if (mb_strlen($text) > 500) {
            echo json_encode(['success' => false, 'error' => '评论过长']);
            break;
        }
        if (containsUrl($text)) {
            echo json_encode(['success' => false, 'error' => '评论不能包含网址']);
            break;
        }
        $hit = matchKeyword($text, $db, $BUILTIN_KEYWORDS);
        if ($hit !== null) {
            echo json_encode(['success' => false, 'error' => '内容包含敏感词，已被拦截']); break;
        }
        
        // 🔒 樱花动漫评论只能回复樱花动漫评论
        if (($parent['source'] ?? '') === 'bangumi') {
            echo json_encode(['success' => false, 'error' => '不能回复 Bangumi 评论']); break;
        }
        
        $stmt = $db->prepare("INSERT INTO comments (subject_id, episode, parent_id, text, sender, uid, status, source, created_at)
            VALUES (?, ?, ?, ?, ?, ?, 'active', 'server', ?)");
        $stmt->bindValue(1, $parent['subject_id'], SQLITE3_INTEGER);
        $stmt->bindValue(2, $parent['episode'], SQLITE3_INTEGER);
        $stmt->bindValue(3, $commentId, SQLITE3_INTEGER);
        $stmt->bindValue(4, $text, SQLITE3_TEXT);
        $stmt->bindValue(5, $sender, SQLITE3_TEXT);
        $stmt->bindValue(6, $uid, SQLITE3_TEXT);
        $stmt->bindValue(7, time(), SQLITE3_INTEGER);
        $stmt->execute();
        echo json_encode(['success' => true, 'id' => $db->lastInsertRowID(), 'message' => '回复已发布']);
        break;
    }

    case 'list': {
        $subjectId = (int)($_GET['id'] ?? 0);
        $episode = (int)($_GET['ep'] ?? 0);
        if ($subjectId <= 0) {
            echo json_encode(['success' => false, 'error' => '缺少 id']);
            break;
        }
        $stmt = $db->prepare("SELECT id, episode, parent_id, text, sender, uid, avatar, rating, votes, source, pinned, created_at
            FROM comments WHERE subject_id = ? AND episode = ? AND status = 'active'
            ORDER BY pinned DESC, votes DESC, created_at ASC LIMIT 500");
        $stmt->bindValue(1, $subjectId, SQLITE3_INTEGER);
        $stmt->bindValue(2, $episode, SQLITE3_INTEGER);
        $res = $stmt->execute();
        $list = [];
        while ($row = $res->fetchArray(SQLITE3_ASSOC)) {
            $list[] = [
                'id' => (int)$row['id'],
                'episode' => (int)$row['episode'],
                'parentId' => (int)$row['parent_id'],
                'text' => $row['text'],
                'sender' => $row['sender'],
                'uid' => $row['uid'],
                'avatar' => $row['avatar'],
                'rating' => (int)$row['rating'],
                'votes' => (int)$row['votes'],
                'source' => $row['source'],
                'pinned' => (int)$row['pinned'],
                'createdAt' => (int)$row['created_at'],
            ];
        }
        echo json_encode([
            'success' => true,
            'comments' => $list,
            'admin_nickname' => (string)$db->querySingle("SELECT value FROM settings WHERE key = 'admin_nickname'"),
        ], JSON_UNESCAPED_UNICODE);
        break;
    }

    case 'vote': {
        $input = readBody();
        $id = (int)($input['id'] ?? 0);
        $value = (int)($input['value'] ?? 1);
        $stmt = $db->prepare("UPDATE comments SET votes = MAX(0, votes + ?) WHERE id = ?");
        $stmt->bindValue(1, $value > 0 ? 1 : -1, SQLITE3_INTEGER);
        $stmt->bindValue(2, $id, SQLITE3_INTEGER);
        $stmt->execute();
        echo json_encode(['success' => true]);
        break;
    }

    case 'remove':
    case 'restore': {
        $input = readBody();
        if (($input['admin_key'] ?? '') !== COMMENT_ADMIN_KEY) {
            echo json_encode(['success' => false, 'error' => '无权操作']);
            break;
        }
        $id = (int)($input['id'] ?? 0);
        if ($id <= 0) {
            echo json_encode(['success' => false, 'error' => '缺少 id']);
            break;
        }
        $status = $action === 'remove' ? 'removed' : 'active';
        $stmt = $db->prepare("UPDATE comments SET status = ? WHERE id = ?");
        $stmt->bindValue(1, $status, SQLITE3_TEXT);
        $stmt->bindValue(2, $id, SQLITE3_INTEGER);
        $stmt->execute();
        echo json_encode(['success' => true]);
        break;
    }

    // 管理员：置顶/取消置顶评论
    case 'set_pin': {
        $input = readBody();
        if (($input['admin_key'] ?? '') !== COMMENT_ADMIN_KEY) {
            echo json_encode(['success' => false, 'error' => '无权操作']);
            break;
        }
        $id = (int)($input['id'] ?? 0);
        $pinned = !empty($input['pinned']) ? 1 : 0;
        if ($id <= 0) {
            echo json_encode(['success' => false, 'error' => '缺少 id']);
            break;
        }
        $stmt = $db->prepare("UPDATE comments SET pinned = ? WHERE id = ?");
        $stmt->bindValue(1, $pinned, SQLITE3_INTEGER);
        $stmt->bindValue(2, $id, SQLITE3_INTEGER);
        $stmt->execute();
        echo json_encode(['success' => true, 'pinned' => $pinned]);
        break;
    }

    // 管理员：设置自定义昵称（置顶评论显示的名字）
    case 'set_admin_nickname': {
        $input = readBody();
        if (($input['admin_key'] ?? '') !== COMMENT_ADMIN_KEY) {
            echo json_encode(['success' => false, 'error' => '无权操作']);
            break;
        }
        $nickname = trim((string)($input['nickname'] ?? ''));
        if ($nickname === '' || mb_strlen($nickname) > 20) {
            echo json_encode(['success' => false, 'error' => '昵称无效']);
            break;
        }
        $stmt = $db->prepare("INSERT OR REPLACE INTO settings (key, value) VALUES ('admin_nickname', ?)");
        $stmt->bindValue(1, $nickname, SQLITE3_TEXT);
        $stmt->execute();
        echo json_encode(['success' => true, 'nickname' => $nickname]);
        break;
    }

    default:
        echo json_encode(['success' => false, 'error' => '未知操作', 'hint' => 'action=add|reply|list|vote|remove|restore']);
}
