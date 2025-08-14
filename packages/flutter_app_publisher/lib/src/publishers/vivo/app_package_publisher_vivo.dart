import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_app_publisher/src/publishers/util.dart';
import 'package:http/http.dart' as http;

const kEnvVivoKey = 'VIVO_ACCESS_KEY';
const kEnvVivoSecret = 'VIVO_ACCESS_SECRET';

///  doc [https://dev.vivo.com.cn/documentCenter/doc/326]
class AppPackagePublisherVivo extends AppPackagePublisher {
  @override
  String get name => 'vivo';

  String? client;
  String? access;
  late Map<String, String> globalEnvironment;

  @override
  Future<PublishResult> publish(
    FileSystemEntity fileSystemEntity, {
    Map<String, String>? environment,
    Map<String, dynamic>? publishArguments,
    PublishProgressCallback? onPublishProgress,
  }) async {
    globalEnvironment = environment ?? Platform.environment;
    File file = fileSystemEntity as File;
    client = globalEnvironment[kEnvVivoKey];
    access = globalEnvironment[kEnvVivoSecret];
    if ((client ?? '').isEmpty) {
      throw PublishError('Missing `$kEnvVivoKey` environment variable.');
    }
    if ((access ?? '').isEmpty) {
      throw PublishError('Missing `$kEnvVivoSecret` environment variable.');
    }
    Map uploadInfo = await uploadApp(
        globalEnvironment[kEnvPkgName]!, file, onPublishProgress);
    // print('上传文件成功：${jsonEncode(uploadInfo)}');
    // //提交审核信息
    Map submitInfo = await submit(uploadInfo, {});
    return PublishResult(url: globalEnvironment[kEnvAppName]! + name + '提交成功}');
  }

  Future<Map> submit(Map uploadInfo, Map appInfo) async {
    Map<String, dynamic> params = {};
    params['packageName'] = globalEnvironment[kEnvPkgName];
    params['versionCode'] = globalEnvironment[kEnvVersionCode];
    params['apk'] = uploadInfo['data']['serialnumber'];
    params['fileMd5'] = uploadInfo['data']['fileMd5'];
    params['onlineType'] = 1;
    params['updateDesc'] = globalEnvironment[kEnvUpdateLog];

    params['method'] = 'app.sync.update.app';
    params['access_key'] = client!;
    params['format'] = 'json';
    params['timestamp'] = (DateTime.now().millisecondsSinceEpoch).toString();
    params['v'] = '1.0';
    params['sign_method'] = 'hmac';
    params['target_app_key'] = 'developer';

    params.removeWhere((key, value) => value == null);
    params['sign'] = PublishUtil.oppoSign(access!, params);
    var map = await PublishUtil.sendRequest(
      'https://developer-api.vivo.com.cn/router/rest',
      params,
      isGet: false,
    );
    if (map?["code"] == 0) {
      return map!;
    } else {
      throw PublishError("请求submit失败");
    }
  }

  ///上传文件
  Future<Map> uploadApp(
    String pkg,
    File file,
    PublishProgressCallback? onPublishProgress,
  ) async {
    var request = http.MultipartRequest(
        'POST', Uri.parse('https://developer-api.vivo.com.cn/router/rest'));
    request.fields['method'] = 'app.upload.apk.app';
    request.fields['access_key'] = client!;
    request.fields['format'] = 'json';
    request.fields['timestamp'] =
        (DateTime.now().millisecondsSinceEpoch).toString();
    request.fields['v'] = '1.0';
    request.fields['sign_method'] = 'hmac';
    request.fields['target_app_key'] = 'developer';
    request.fields['packageName'] = pkg;
    var fileMd5 = md5.convert(file.readAsBytesSync()).toString();
    request.fields['fileMd5'] = fileMd5;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    request.fields['sign'] = PublishUtil.oppoSign(access!, request.fields);
    var response = await request.send();
    if (response.statusCode == 200) {
      String content = await response.stream.bytesToString();
      Map responseMap = jsonDecode(content);
      if (responseMap["code"] == 0) {
        return responseMap;
      } else {
        throw PublishError(content);
      }
    } else {
      // 处理错误的响应
      throw PublishError("请求失败：${response.statusCode}");
    }
  }
}
