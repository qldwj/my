
import 'dart:convert';
import 'dart:io';

/// 樱花动漫扫码登录 PHP 后端版
/// qlyyz.xyz/api/qr/
class QrLoginService {

  static const String base =
      "https://qlyyz.xyz/api/qr/";

  static const String scheme = "yhdmgz";


  static bool canHandle(String value) {
    try {
      final uri = Uri.parse(value);
      return uri.scheme == scheme &&
          uri.host == "login";
    } catch (_) {
      return false;
    }
  }


  static String? getCode(String value) {
    try {
      final uri = Uri.parse(value);

      if (!canHandle(value)) return null;

      return uri.queryParameters["code"];
    } catch (_) {
      return null;
    }
  }


  /// 已登录设备生成二维码数据
  static Future<Map<String,dynamic>> createQr() async {

    final client = HttpClient();

    final request = await client.postUrl(
      Uri.parse("${base}create.php")
    );

    final response = await request.close();

    final body =
        await response.transform(utf8.decoder).join();

    client.close();

    return jsonDecode(body);
  }


  /// 扫码设备直接确认登录
  static Future<bool> confirmLogin(
      String code,
      String userToken
  ) async {

    final client = HttpClient();

    final request = await client.postUrl(
      Uri.parse("${base}confirm.php")
    );

    request.headers.contentType =
        ContentType.json;


    request.write(jsonEncode({

      "code": code,

      "token": userToken

    }));


    final response = await request.close();

    final body =
        await response.transform(utf8.decoder).join();

    client.close();


    final data=jsonDecode(body);


    return data["success"]==true;
  }



  /// 被登录设备轮询状态
  static Future<Map<String,dynamic>> check(
      String code
  ) async {


    final client=HttpClient();


    final request =
        await client.getUrl(
          Uri.parse(
            "${base}check.php?code=$code"
          )
        );


    final response =
        await request.close();


    final body =
        await response.transform(
            utf8.decoder
        ).join();


    client.close();


    return jsonDecode(body);

  }

}
