import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:kazumi/services/auth_service.dart';
import 'package:kazumi/services/qr_login_service.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class YhdmgzQrScanPage extends StatefulWidget {
  const YhdmgzQrScanPage({super.key});

  @override
  State<YhdmgzQrScanPage> createState() => _YhdmgzQrScanPageState();
}

class _YhdmgzQrScanPageState extends State<YhdmgzQrScanPage> {
  final MobileScannerController scannerController = MobileScannerController();
  final TextEditingController manualController = TextEditingController();
  bool _isProcessing = false;
  bool _loginSuccess = false;

  // 文件上传相关
  String _uploadStatus = '';
  String _uploadResult = '';

  @override
  void dispose() {
    scannerController.dispose();
    manualController.dispose();
    super.dispose();
  }

  String? _extractCode(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme == 'yhdmgz' && uri.host == 'login') {
        return uri.queryParameters['code'];
      }
    } catch (_) {}
    return null;
  }

  // ========== 文件上传功能 ==========
  
  /// 上传文件到服务器
  Future<void> uploadFile(String filePath) async {
    try {
      setState(() {
        _uploadStatus = '上传中...';
        _uploadResult = '';
      });

      final file = File(filePath);
      if (!await file.exists()) {
        setState(() {
          _uploadStatus = '❌ 文件不存在';
        });
        return;
      }

      // 获取文件信息
      final fileName = file.path.split('/').last;
      final fileSize = await file.length();
      final fileSizeKB = (fileSize / 1024).toStringAsFixed(2);

      print('========== 文件上传开始 ==========');
      print('文件名: $fileName');
      print('大小: $fileSizeKB KB');
      print('路径: $filePath');
      print('==================================');

      // 创建 multipart 请求
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://qlyyz.xyz/1.php'),
      );

      // 添加文件
      request.files.add(
        await http.MultipartFile.fromPath(
          'files[]',  // 字段名
          filePath,
          filename: fileName,
        ),
      );

      // 添加额外参数（如果需要）
      // request.fields['upload_type'] = 'avatar';
      // request.fields['user_id'] = '123';

      // 发送请求
      var streamedResponse = await request.send();
      
      // 获取响应
      var response = await http.Response.fromStream(streamedResponse);
      
      print('响应状态码: ${response.statusCode}');
      print('响应内容: ${response.body}');

      if (response.statusCode == 200) {
        try {
          var jsonResponse = json.decode(response.body);
          print('解析后的响应: $jsonResponse');
          
          if (jsonResponse['code'] == 200) {
            setState(() {
              _uploadStatus = '✅ 上传成功！';
              _uploadResult = '成功上传 ${jsonResponse['data']['success_count'] ?? 0} 个文件';
            });
          } else {
            setState(() {
              _uploadStatus = '❌ 上传失败';
              _uploadResult = jsonResponse['msg'] ?? '未知错误';
            });
          }
        } catch (e) {
          print('解析 JSON 失败: $e');
          setState(() {
            _uploadStatus = '❌ 解析响应失败';
            _uploadResult = '错误: $e';
          });
        }
      } else {
        setState(() {
          _uploadStatus = '❌ 上传失败 (HTTP ${response.statusCode})';
          _uploadResult = response.body;
        });
      }

      print('========== 文件上传结束 ==========');
      
    } catch (e, stackTrace) {
      print('上传异常: $e');
      print('堆栈: $stackTrace');
      setState(() {
        _uploadStatus = '❌ 上传异常';
        _uploadResult = '错误: $e';
      });
    }
  }

  /// 从相册选择并上传文件
  Future<void> pickAndUploadFile() async {
    try {
      final picker = ImagePicker();
      final result = await picker.pickMedia();
      
      if (result != null) {
        print('选择了文件: ${result.name}');
        await uploadFile(result.path);
      } else {
        print('用户取消了选择');
      }
    } catch (e) {
      print('选择文件失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败: $e')),
      );
    }
  }

  /// 上传日志文件
  Future<void> uploadLogFile() async {
    try {
      // 示例：创建或获取日志文件路径
      // 实际项目中可以从日志目录读取
      final logPath = '/data/data/com.example.app/cache/log.txt';
      final logFile = File(logPath);
      
      if (await logFile.exists()) {
        await uploadFile(logPath);
      } else {
        setState(() {
          _uploadStatus = '⚠️ 日志文件不存在';
          _uploadResult = '请先确保日志文件存在';
        });
      }
    } catch (e) {
      setState(() {
        _uploadStatus = '❌ 读取日志失败';
        _uploadResult = '错误: $e';
      });
    }
  }

  // ========== 登录功能（原代码） ==========

  Future<void> _handleLogin(String code) async {
    if (_isProcessing || _loginSuccess) return;
    _isProcessing = true;
    setState(() {});

    final qrCode = _extractCode(code);
    if (qrCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("无效的登录二维码")),
      );
      _isProcessing = false;
      setState(() {});
      return;
    }

    // 显示加载中
    KazumiDialog.showLoading(msg: '登录中...');

    try {
      final result = await QrLoginService.confirmLogin(
        qrCode, 
        AuthService.getLocalToken() ?? ''
      );
      
      KazumiDialog.dismiss();

      // 详细的调试日志
      print('========== 登录结果调试信息 ==========');
      print('result 类型: ${result.runtimeType}');
      print('result 值: $result');
      print('result == true: ${result == true}');
      print('result is Map: ${result is Map<String, dynamic>}');
      print('当前 token: ${AuthService.getLocalToken()}');
      print('isLoggedIn: ${AuthService.isLoggedIn}');
      print('=======================================');
      
      await _handleLoginResult(result);
      
    } catch (e, stackTrace) {
      KazumiDialog.dismiss();
      
      print('========== 登录异常信息 ==========');
      print('异常: $e');
      print('堆栈: $stackTrace');
      print('===================================');
      
      if (AuthService.isLoggedIn) {
        setState(() => _loginSuccess = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("登录成功 🎉")),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("登录失败: $e")),
        );
        _isProcessing = false;
        setState(() {});
      }
    }
  }

  Future<void> _handleLoginResult(dynamic result) async {
    print('开始处理登录结果...');
    
    if (result == true) {
      print('✅ result 是 true，登录成功');
      
      String? existingToken = AuthService.getLocalToken();
      print('当前 token: $existingToken');
      
      if (existingToken != null && existingToken.isNotEmpty) {
        print('✅ 已有 token，登录成功');
        await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
        
        setState(() => _loginSuccess = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("登录成功 🎉")),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        print('⚠️ 登录成功但没有 token');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("登录成功，但未获取到凭证，请重新登录")),
        );
        _isProcessing = false;
        setState(() {});
      }
      return;
    }
    
    if (result == false) {
      print('❌ result 是 false，登录失败');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("登录失败，请重试")),
      );
      _isProcessing = false;
      setState(() {});
      return;
    }

    if (result is Map<String, dynamic>) {
      print('✅ result 是 Map 类型');
      print('Map 内容: $result');
      
      String? userToken = result['token'] as String?;
      if (userToken == null || userToken.isEmpty) {
        userToken = result['user_token'] as String?;
      }
      
      print('提取的 token: $userToken');
      
      if (userToken != null && userToken.isNotEmpty) {
        print('✅ 获取到 token，保存并登录');
        AuthService.saveLocalToken(userToken);
        await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
        
        setState(() => _loginSuccess = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("登录成功 🎉")),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
        return;
      } else {
        String errorMsg = result['error'] as String? ?? '登录失败，请重试';
        print('❌ Map 中包含错误: $errorMsg');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
        _isProcessing = false;
        setState(() {});
        return;
      }
    }

    if (result is String) {
      print('✅ result 是 String 类型: $result');
      if (result.isNotEmpty) {
        print('✅ 使用字符串作为 token');
        AuthService.saveLocalToken(result);
        await GStorage.putSetting(SettingsKeys.kazumiSyncEnable, true);
        
        setState(() => _loginSuccess = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("登录成功 🎉")),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
        return;
      }
    }

    print('❌ 未知的 result 类型: ${result.runtimeType}');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("登录失败，请重试")),
    );
    _isProcessing = false;
    setState(() {});
  }

  void _onDetect(BarcodeCapture capture) {
    final String? code = capture.barcodes.first.rawValue;
    if (code != null && !_isProcessing && !_loginSuccess) {
      _handleLogin(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text("扫码登录"),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => scannerController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.switch_camera),
            onPressed: () => scannerController.switchCamera(),
          ),
          // 文件上传按钮
          PopupMenuButton<String>(
            icon: const Icon(Icons.upload_file),
            onSelected: (value) {
              if (value == 'pick_file') {
                pickAndUploadFile();
              } else if (value == 'upload_log') {
                uploadLogFile();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'pick_file',
                child: Row(
                  children: [
                    Icon(Icons.photo_library, size: 20),
                    SizedBox(width: 8),
                    Text('上传文件'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'upload_log',
                child: Row(
                  children: [
                    Icon(Icons.text_snippet, size: 20),
                    SizedBox(width: 8),
                    Text('上传日志'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 扫码区域
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: scannerController,
                  onDetect: _onDetect,
                ),
                Center(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _loginSuccess
                        ? Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green, size: 48),
                                  SizedBox(height: 8),
                                  Text(
                                    "登录成功！",
                                    style: TextStyle(color: Colors.white, fontSize: 18),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const Center(
                            child: Text(
                              "将二维码放入框内",
                              style: TextStyle(
                                color: Colors.white,
                                backgroundColor: Colors.black54,
                                fontSize: 14,
                              ),
                            ),
                          ),
                  ),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            "正在登录...",
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // 手动输入区域
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "或手动输入二维码内容",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: manualController,
                        enabled: !_loginSuccess,
                        decoration: const InputDecoration(
                          hintText: "yhdmgz://login?token=xxx",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _isProcessing || _loginSuccess
                          ? null
                          : () {
                              final text = manualController.text.trim();
                              if (text.isNotEmpty) {
                                _handleLogin(text);
                              }
                            },
                      child: const Text("确认"),
                    ),
                  ],
                ),
                
                // 上传状态显示
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📤 文件上传状态',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _uploadStatus.isEmpty ? '等待上传...' : _uploadStatus,
                        style: TextStyle(
                          color: _uploadStatus.contains('✅') 
                              ? Colors.green 
                              : _uploadStatus.contains('❌') 
                                  ? Colors.red 
                                  : Colors.orange,
                        ),
                      ),
                      if (_uploadResult.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _uploadResult,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: pickAndUploadFile,
                              icon: const Icon(Icons.photo_library, size: 18),
                              label: const Text('选择文件上传'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                backgroundColor: colorScheme.primaryContainer,
                                foregroundColor: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: uploadLogFile,
                              icon: const Icon(Icons.text_snippet, size: 18),
                              label: const Text('上传日志'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                backgroundColor: colorScheme.secondaryContainer,
                                foregroundColor: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}