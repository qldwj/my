import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final TextEditingController _contentController = TextEditingController();
  final List<XFile> _selectedFiles = [];
  bool _isSubmitting = false;
  List<dynamic> _feedbacks = [];
  bool _isLoading = false;

  // ⚠️ 替换成你的服务器地址
  static const String _baseUrl = 'http://你的服务器IP或域名';
  static const String _submitUrl = '$_baseUrl/submit.php';
  static const String _listUrl = '$_baseUrl/admin.php?action=getFeedbacks';

  @override
  void initState() {
    super.initState();
    _fetchFeedbacks();
  }

  // 获取所有反馈
  Future<void> _fetchFeedbacks() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse(_listUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          setState(() => _feedbacks = data);
        } else {
          setState(() => _feedbacks = []);
        }
      } else {
        setState(() => _feedbacks = []);
      }
    } catch (e) {
      setState(() => _feedbacks = []);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 选择图片
  Future<void> _pickImages() async {
    if (_selectedFiles.length >= 4) {
      KazumiDialog.showToast(message: '最多只能选择4个文件');
      return;
    }
    final picker = ImagePicker();
    final List<XFile>? picked = await picker.pickMultiImage();
    if (picked != null) {
      setState(() {
        final remaining = 4 - _selectedFiles.length;
        _selectedFiles.addAll(picked.take(remaining));
      });
    }
  }

  // 选择视频
  Future<void> _pickVideo() async {
    if (_selectedFiles.length >= 4) {
      KazumiDialog.showToast(message: '最多只能选择4个文件');
      return;
    }
    final picker = ImagePicker();
    final XFile? picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedFiles.add(picked);
      });
    }
  }

  // 移除文件
  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  // 获取MIME类型
  String? _getMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    if (['jpg', 'jpeg'].contains(ext)) return 'image/jpeg';
    if (ext == 'png') return 'image/png';
    if (ext == 'gif') return 'image/gif';
    if (ext == 'mp4') return 'video/mp4';
    if (ext == 'mov') return 'video/quicktime';
    if (ext == 'avi') return 'video/x-msvideo';
    if (ext == 'webm') return 'video/webm';
    return null;
  }

  // 提交反馈
  Future<void> _submitFeedback() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      KazumiDialog.showToast(message: '请填写反馈内容');
      return;
    }

    // 检查文件大小
    for (var xFile in _selectedFiles) {
      final file = File(xFile.path);
      if (await file.length() > 20 * 1024 * 1024) {
        KazumiDialog.showToast(message: '文件 ${xFile.name} 超过 20MB 限制');
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_submitUrl));
      request.fields['content'] = content;

      for (var xFile in _selectedFiles) {
        final file = File(xFile.path);
        final mimeType = _getMimeType(xFile.name);
        final multipartFile = await http.MultipartFile.fromPath(
          'media[]',
          file.path,
          contentType: mimeType != null ? http.MediaType.parse(mimeType) : null,  // 修复：加上 http.
        );
        request.files.add(multipartFile);
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['success'] == true) {
          KazumiDialog.showToast(message: '反馈提交成功，感谢您的支持！');
          _contentController.clear();
          setState(() => _selectedFiles.clear());
          // 刷新列表
          _fetchFeedbacks();
        } else {
          KazumiDialog.showToast(
            message: '提交失败：${json['error'] ?? '未知错误'}',
          );
        }
      } else {
        KazumiDialog.showToast(message: '服务器响应异常 (${response.statusCode})');
      }
    } catch (e) {
      KazumiDialog.showToast(message: '网络请求失败，请检查网络连接');
      debugPrint('反馈提交错误: $e');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  // 构建单个反馈卡片
  Widget _buildFeedbackItem(Map<String, dynamic> item) {
    final status = item['status'] == 1 ? '已处理' : '待处理';
    final statusColor = item['status'] == 1 ? Colors.green : Colors.orange;
    final reply = item['reply'] ?? '';
    final media = item['media'] ?? [];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item['time'] ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item['content'] ?? '',
              style: const TextStyle(fontSize: 15),
            ),
            if (media.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: media.map<Widget>((url) {
                  final ext = url.toString().split('.').last.toLowerCase();
                  if (['jpg', 'jpeg', 'png', 'gif'].contains(ext)) {
                    return GestureDetector(
                      onTap: () => _showImagePreview(url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          '$_baseUrl/$url',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                        ),
                      ),
                    );
                  } else if (['mp4', 'mov', 'avi', 'webm'].contains(ext)) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: VideoPlayerWidget('$_baseUrl/$url'),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }).toList(),
              ),
            ],
            if (reply.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '官方回复：',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(reply, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 预览图片（简单弹出）
  void _showImagePreview(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.network('$_baseUrl/$url'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('意见反馈'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchFeedbacks,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------- 提交表单 ----------
            const Text(
              '提交反馈',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '请描述您的问题或建议...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('选择图片'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade50,
                    foregroundColor: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _pickVideo,
                  icon: const Icon(Icons.video_library),
                  label: const Text('选择视频'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade50,
                    foregroundColor: Colors.purple.shade700,
                  ),
                ),
              ],
            ),
            if (_selectedFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedFiles.asMap().entries.map((entry) {
                  final index = entry.key;
                  final file = entry.value;
                  return Chip(
                    avatar: const Icon(Icons.insert_drive_file, size: 16),
                    label: Text(file.name.length > 16
                        ? '${file.name.substring(0, 16)}...'
                        : file.name),
                    onDeleted: () => _removeFile(index),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    backgroundColor: Colors.grey.shade100,
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitFeedback,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '提交反馈',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const Divider(height: 32),

            // ---------- 所有反馈列表 ----------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '所有反馈',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: _fetchFeedbacks,
                  child: const Text('刷新'),
                ),
              ],
            ),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_feedbacks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('暂无反馈，快来提交第一条吧！')),
              )
            else
              ..._feedbacks.map((item) => _buildFeedbackItem(item)).toList(),
          ],
        ),
      ),
    );
  }
}

// 简单视频播放器组件（仅显示封面，点击全屏查看）
class VideoPlayerWidget extends StatefulWidget {
  final String url;
  const VideoPlayerWidget(this.url, {super.key});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => Dialog(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: VideoPlayerFullscreen(widget.url),
            ),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.black12,
            child: const Icon(Icons.play_circle_fill, size: 40, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

// 全屏视频播放器（占位，可使用 media_kit 或 video_player 实现）
class VideoPlayerFullscreen extends StatelessWidget {
  final String url;
  const VideoPlayerFullscreen(this.url, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.play_circle_fill, size: 60),
          const SizedBox(height: 8),
          Text('点击播放：$url'),
        ],
      ),
    );
  }
}