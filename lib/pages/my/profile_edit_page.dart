import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/social/social_service.dart';

/// 个人资料编辑页（昵称 / 头像）
///
/// 头像不保存在本机，直接上传服务器（api/log/data/avatars/）。
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final TextEditingController _nicknameController = TextEditingController();
  SocialProfile? _profile;
  bool _uploading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _profile = SocialService.restoreLocalProfile();
    _nicknameController.text = _profile?.nickname ?? '';
  }

  Future<void> _pickAvatar() async {
    if (_uploading) return;
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      KazumiDialog.showToast(message: '图片过大（最大 2MB）');
      return;
    }
    setState(() => _uploading = true);
    final error = await SocialService.uploadAvatar(base64Encode(bytes));
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _profile = SocialService.myProfile;
    });
    if (error == null) {
      KazumiDialog.showToast(message: '✅ 头像已更新');
    } else {
      KazumiDialog.showToast(message: '❌ $error');
    }
  }

  Future<void> _saveNickname() async {
    final name = _nicknameController.text.trim();
    if (name.isEmpty || name == _profile?.nickname) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _saving = true);
    final error = await SocialService.updateProfile(nickname: name);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      _profile = SocialService.myProfile;
      KazumiDialog.showToast(message: '✅ 昵称已更新');
      Navigator.of(context).maybePop();
    } else {
      KazumiDialog.showToast(message: '❌ $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatar = _profile?.avatar ?? '';
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('编辑资料'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),
          // 头像
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  ClipOval(
                    child: avatar.isNotEmpty
                        ? NetworkImgLayer(
                            width: 96, height: 96, src: avatar)
                        : Container(
                            width: 96,
                            height: 96,
                            color: colorScheme.primaryContainer,
                            child: Icon(Icons.person_rounded,
                                size: 56,
                                color: colorScheme.onPrimaryContainer),
                          ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.photo_camera_rounded,
                              size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _profile == null ? '' : 'uid: ${_profile!.uid}',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nicknameController,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: '昵称',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _saveNickname,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
    );
  }
}
