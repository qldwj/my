import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/bangumi_avatar.dart';
import 'package:kazumi/modules/staff/staff_item.dart';

class StaffCard extends StatelessWidget {
  const StaffCard({
    super.key,
    required this.staffFullItem,
  });

  final StaffFullItem staffFullItem;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: BangumiAvatar(
        url: staffFullItem.staff.images?.grid == null
            ? 'https://bangumi.tv/img/info_only.png'
            : staffFullItem.staff.images!.grid,
        size: 40,
      ),
      title: Text(
        staffFullItem.staff.name,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: staffFullItem.staff.nameCN.isNotEmpty
          ? Text(staffFullItem.staff.nameCN)
          : null,
      trailing: Text(staffFullItem.positions.isNotEmpty
          ? (staffFullItem.positions[0].type.cn)
          : ''),
    );
  }
}
