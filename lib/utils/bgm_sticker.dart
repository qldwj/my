/// BGM 表情（贴纸）本地资源映射。
///
/// 图片取自 Ani 项目的 composeResources/drawable（bgm_01.png … bgm_23.gif），
/// 与官方 Kazumi 一致使用 `(bgmN)` 作为文本编码。原先 mp 直接引用
/// lain.bgm.tv 的远程 gif 链接（现已失效），现改为打包到本地的资源。
class BgmSticker {
  static const String _dir = 'assets/bgm_stickers/';

  /// 根据表情 id（如 'bgm1'）返回本地资源路径；不存在返回 null。
  /// 资源文件名沿用 Ani 的命名：bgm_01.png / bgm_11.gif / bgm_23.gif
  static String? assetFor(String id) {
    final n = int.tryParse(id.replaceFirst(RegExp(r'^bgm'), ''));
    if (n == null || n < 1 || n > 23) return null;
    final name = 'bgm_${n.toString().padLeft(2, '0')}';
    // bgm_11 与 bgm_23 为 gif，其余为 png
    if (n == 11 || n == 23) return '$_dir$name.gif';
    return '$_dir$name.png';
  }

  /// 可用的全部表情 id（bgm1..bgm23）
  static const List<String> allIds = [
    'bgm1', 'bgm2', 'bgm3', 'bgm4', 'bgm5', 'bgm6', 'bgm7', 'bgm8', 'bgm9',
    'bgm10', 'bgm11', 'bgm12', 'bgm13', 'bgm14', 'bgm15', 'bgm16', 'bgm17',
    'bgm18', 'bgm19', 'bgm20', 'bgm21', 'bgm22', 'bgm23',
  ];
}
