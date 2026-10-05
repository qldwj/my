enum SuperResolutionMode {
  off(
    storageValue: 1,
    label: '关闭',
    description: '默认禁用画质增强',
  ),
  light(
    storageValue: 4,
    label: '轻量增强',
    description: '去色带 + 轻量锐化，所有设备可流畅运行',
  ),
  balanced(
    storageValue: 5,
    label: '均衡档',
    description: '画质比质量档好一点，性能比效率档省一点',
  ),
  efficiency(
    storageValue: 2,
    label: '效率档',
    description: '默认启用基于Anime4K的超分辨率 (效率优先)',
  ),
  quality(
    storageValue: 3,
    label: '质量档',
    description: '默认启用基于Anime4K的超分辨率 (质量优先)',
  );

  const SuperResolutionMode({
    required this.storageValue,
    required this.label,
    required this.description,
  });

  final int storageValue;
  final String label;
  final String description;

  static SuperResolutionMode fromStorageValue(int value) {
    return SuperResolutionMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => SuperResolutionMode.off,
    );
  }
}
