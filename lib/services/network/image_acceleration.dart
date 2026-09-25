enum ImageAcceleration {
  direct,
  ech,
  mirror;

  static ImageAcceleration fromSetting(String value) =>
      values.firstWhere((mode) => mode.name == value, orElse: () => ech);

  /// 显示名称
  String get label => switch (this) {
        ImageAcceleration.direct => '直连',
        ImageAcceleration.ech => 'ECH',
        ImageAcceleration.mirror => '镜像',
      };

  /// 说明文字
  String get description => switch (this) {
        ImageAcceleration.direct => '直接从 Bangumi 加载图片',
        ImageAcceleration.ech => '通过 ECH 加载 Bangumi 图片，推荐使用',
        ImageAcceleration.mirror => '通过图片镜像服务加载 Bangumi 图片',
      };
}
