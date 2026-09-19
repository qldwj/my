// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collect_module.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CollectedBangumiAdapter extends TypeAdapter<CollectedBangumi> {
  @override
  final typeId = 3;

  @override
  CollectedBangumi read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CollectedBangumi(
      fields[0] as BangumiItem,
      // ⚠️ 兼容旧版本 / 其他端上传的备份：个别记录的 time 缺失（null）。
      // 原本直接 `as DateTime` 会抛
      // “type 'Null' is not a subtype of type 'DateTime' in type cast”，
      // 导致整份收藏同步直接失败（日志：WebDav: get collectibles failed）。
      // 这里退化为 epoch，保证记录仍能被读出并参与合并。
      fields[1] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
      (fields[2] as num?)?.toInt() ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, CollectedBangumi obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.bangumiItem)
      ..writeByte(1)
      ..write(obj.time)
      ..writeByte(2)
      ..write(obj.type);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollectedBangumiAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
