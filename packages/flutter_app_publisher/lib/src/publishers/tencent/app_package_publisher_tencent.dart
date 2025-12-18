import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:http/http.dart' as http;


const kEnvAppName = 'APP_NAME';
const kEnvTencentAppUserId = 'TENCENT_USER_ID';
const kEnvTencentAccessSecret = 'TENCENT_ACCESS_SECRET';
const kEnvTencentAppId = 'TENCENT_APP_ID';
const kEnvPkgName = 'PKG_NAME';
const kEnvAppMD5 = 'TENCENT_APP_MD5';
const kEnvUpdateLog = 'UPDATE_LOG';

const domain = 'https://p.open.qq.com/open_file/developer_api'; // 正式环境接口域名

///  doc [https://wikinew.open.qq.com/index.html#/iwiki/4015262492]
class AppPackagePublisherTencent extends AppPackagePublisher {
  @override
  String get name => 'tencent';
  String? userId;
  String? accessSecret;
  String? appName;
  String? pkgName;
  String? appId;
  String? appMD5;
  String? appUpdateLog;

  late Map<String, String> globalEnvironment;

  @override
  Future<PublishResult> publish(
    FileSystemEntity fileSystemEntity, {
    Map<String, String>? environment,
    Map<String, dynamic>? publishArguments,
    PublishProgressCallback? onPublishProgress,
  }) async {

    try {
      File file = fileSystemEntity as File;

      globalEnvironment = environment ?? Platform.environment;
      userId = globalEnvironment[kEnvTencentAppUserId];
      appName = globalEnvironment[kEnvAppName];
      pkgName = globalEnvironment[kEnvPkgName];
      appId = globalEnvironment[kEnvTencentAppId];
      accessSecret = globalEnvironment[kEnvTencentAccessSecret];
      appMD5 = globalEnvironment[kEnvAppMD5];
      appUpdateLog = globalEnvironment[kEnvUpdateLog];

      Map? appInfo = await getAppInfo();
      Map? upLoadInfo = await getUpLoadFileInfo(appInfo);
      if(upLoadInfo != null){
        await uploadFile(upLoadInfo["pre_sign_url"],file);
        String serialNumber = upLoadInfo["serial_number"];
        await updateAppInfo(serialNumber);

      }else{
      }
      return PublishResult(url: globalEnvironment[kEnvAppName]! + name + '提交成功}');
    }  catch (e) {
      print("app提交失败========$name$e=========");
      exit(1);
    }
  }


  /// 计算签名
  String calSign(String key, Map<String, dynamic> data) {
    // 将参数按 key 排序
    final sortedKeys = data.keys.toList()..sort();

    // 拼接成 key=value&key=value
    final signStr = sortedKeys.map((k) => '$k=${data[k]}').join('&');

    // HMAC-SHA256 计算
    final hmacSha256 = Hmac(sha256, utf8.encode(key));
    final digest = hmacSha256.convert(utf8.encode(signStr));
    return digest.toString();
  }

  Future<Map?> getAppInfo() async {
    // 公共参数
    final data = <String, String>{
      'user_id': userId!,
      'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      // 业务参数
      'pkg_name': pkgName!,
      'app_id': appId!
    };

    // 计算签名
    final sign = calSign(accessSecret!, data);
    print('api sign: $sign');
    data['sign'] = sign;

    // 发送 POST 请求
    final uri = Uri.parse('$domain/query_app_detail');
    try {
      final response = await http.post(
        uri,
        headers: header(),
        body: data,
      );
      String content = response.body;
      Map responseMap = jsonDecode(content);
      if (responseMap['ret'] == 0) {
        String content = response.body;
        Map responseMap = jsonDecode(content);
        // print('query_app_detail======$responseMap====');
        return responseMap;
      } else {
        throw PublishError(content);
      }
    } catch (e) {
      print('Error sending request: $e');
    }
    return null;
  }

  Future<Map?> getUpLoadFileInfo(Map? appInfo) async {
    // 公共参数
    final data = <String, String>{
      'user_id': userId!,
      'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      // 业务参数
      'pkg_name': pkgName!,
      'app_id': appId!,
      'file_type':'apk',
      'file_name':'$appName.apk',
    };

    // 计算签名
    final sign = calSign(accessSecret!, data);
    print('api sign: $sign');
    data['sign'] = sign;

    // 发送 POST 请求
    final uri = Uri.parse('$domain/get_file_upload_info');
    try {
      final response = await http.post(
        uri,
        headers: header(),
        body: data,
      );
      String content = response.body;
      Map responseMap = jsonDecode(content);
      if (responseMap['ret'] == 0) {
        String content = response.body;
        Map responseMap = jsonDecode(content);
        // print('get_file_upload_info====$responseMap=====');
        return responseMap;
      } else {
        throw PublishError(content);
      }
    } catch (e) {
      print('Error sending request: $e');
    }
    return null;
  }


  Map<String, String>? header(){
    return {'Content-Type': 'application/x-www-form-urlencoded'};
  }

  /// 上传文件到 COS（PUT 预签名 URL）
  Future<void> uploadFile(String preSignUrl, File file) async {
    if (!await file.exists()) {
      throw Exception('File not found: tencent');
    }

    final fileBytes = await file.readAsBytes();

    final response = await http.put(
      Uri.parse(preSignUrl),
      headers: {
        'Content-Type': 'application/octet-stream',
      },
      body: fileBytes,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Upload failed: ${response.statusCode} ${response.reasonPhrase}',
      );
    }
  }


  Future<Map?> updateAppInfo(String? serialNumber) async {
    // 公共参数
    final data = <String, dynamic>{
      'user_id': userId!,
      'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      // 业务参数
      'pkg_name': pkgName!,
      'app_id': appId!,
      'apk32_flag': '2',
      'deploy_type': '1',//立即发布
      'apk64_flag': '1',
      'apk64_file_serial_number':serialNumber,
      'apk64_file_md5':appMD5,
      'feature':appUpdateLog
    };
    // 计算签名
    final sign = calSign(accessSecret!, data);
    print('api sign: $sign');
    data['sign'] = sign;

    // 发送 POST 请求
    final uri = Uri.parse('$domain/update_app');
    try {
      final response = await http.post(
        uri,
        headers: header(),
        body: data,
      );
      String content = response.body;
      Map responseMap = jsonDecode(content);
      if (responseMap['ret'] == 0) {
        String content = response.body;
        Map responseMap = jsonDecode(content);
        // print('update_app======$responseMap====');
        return responseMap;
      } else {
        throw PublishError(content);
      }
    } catch (e) {
      print('Error sending request: $e');
    }
    return null;
  }



}
