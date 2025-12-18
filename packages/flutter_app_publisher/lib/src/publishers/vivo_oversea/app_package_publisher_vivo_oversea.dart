import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_app_publisher/src/publishers/util.dart';
import 'package:http/http.dart' as http;

const kEnvVivoOverseaKey = 'VIVO_OVERSEA_ACCESS_KEY';
const kEnvVivoOverseaSecret = 'VIVO_OVERSEA_ACCESS_SECRET';

///  doc [https://developer.vivo.com/doc/detail?id=95]
class AppPackagePublisherVivoOversea extends AppPackagePublisher {
  @override
  String get name => 'vivo_oversea';

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
    try {
      globalEnvironment = environment ?? Platform.environment;
      File file = fileSystemEntity as File;
      client = globalEnvironment[kEnvVivoOverseaKey];
      access = globalEnvironment[kEnvVivoOverseaSecret];
      if ((client ?? '').isEmpty) {
        throw PublishError('Missing `$kEnvVivoOverseaKey` environment variable.');
      }
      print("-----$access----$client");
      if ((access ?? '').isEmpty) {
        throw PublishError(
            'Missing `$kEnvVivoOverseaSecret` environment variable.');
      }
      Map uploadInfo = await uploadApp(
          globalEnvironment[kEnvPkgName]!, file, onPublishProgress);
      print("aaaa");
      print('上传文件成功：${jsonEncode(uploadInfo)}');
      // //提交审核信息
      await updateInfo(uploadInfo);
      await submit();
      return PublishResult(url: globalEnvironment[kEnvAppName]! + name + '提交成功}');
    }  catch (e) {
      print("app提交失败========$name$e=========");
      exit(1);
    }
  }



  Future updateInfo(Map uploadInfo) async {
    Map<String, dynamic> params = {};
    params['packageName'] = globalEnvironment[kEnvPkgName];
    params['apk'] = uploadInfo['data']['serialNumber'];
    params['method'] = 'app.update.basic.info';
    params['access_key'] = client!;
    params['format'] = 'json';
    params['timestamp'] = (DateTime.now().millisecondsSinceEpoch).toString();
    params['version'] = '1.0';
    params['sign_method'] = 'hmac-sha256';
    params['target_app_key'] = 'developer';

    params.removeWhere((key, value) => value == null);
    params['sign'] = sign(params,access!);
    var map = await PublishUtil.sendRequest(
      'https://developer-api.vivo.com/router/rest',
      params,
      isGet: false,
    );
    if (map?["code"] == "0") {
    } else {
      throw PublishError("请求submit失败");
    }
  }

  Future<Map> submit() async {
    Map<String, dynamic> params = {};
    params['packageName'] = globalEnvironment[kEnvPkgName];
    params['onlineType'] = 1;
    params['method'] = 'app.update.submit';
    params['access_key'] = client!;
    params['format'] = 'json';
    params['timestamp'] = (DateTime.now().millisecondsSinceEpoch).toString();
    params['version'] = '1.0';
    params['sign_method'] = 'hmac-sha256';
    params['target_app_key'] = 'developer';

    params.removeWhere((key, value) => value == null);
    params['sign'] = PublishUtil.oppoSign(access!, params);
    var map = await PublishUtil.sendRequest(
      'https://developer-api.vivo.com/router/rest',
      params,
      isGet: false,
    );
    if (map?["code"] == "0") {
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
        'POST', Uri.parse('https://developer-api.vivo.com/router/rest'));
    request.fields['method'] = 'app.upload.apk';
    request.fields['access_key'] = client!;
    request.fields['format'] = 'json';
    request.fields['timestamp'] =
        (DateTime.now().millisecondsSinceEpoch).toString();
    request.fields['version'] = '1.0';
    request.fields['sign_method'] = 'hmac-sha256';
    request.fields['target_app_key'] = 'developer';
    request.fields['packageName'] = pkg;
    var fileMd5 = md5.convert(file.readAsBytesSync()).toString();
    request.fields['fileMd5'] = fileMd5;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    request.fields['sign'] = PublishUtil.oppoSign(access!, request.fields);
    var response = await request.send();
    print("=====$response=====");
    if (response.statusCode == 200) {
      String content = await response.stream.bytesToString();
      Map responseMap = jsonDecode(content);
      if (responseMap["code"] == "0") {
        return responseMap;
      } else {
        throw PublishError(content);
      }
    } else {
      // 处理错误的响应
      throw PublishError("请求失败：${response.statusCode}");
    }
  }




  String sign(Map<String, dynamic> paramsMap, String accessSecret) {
    var sortedKeys = SplayTreeMap<String, dynamic>.from(paramsMap).keys;
    List<String> paramList = [];
    for (var key in sortedKeys) {
      var value = paramsMap[key];
      if (value == null) {
        continue;
      }
      paramList.add('$key=${value.toString()}');
    }
    String params = paramList.join("&");
    return hmacSHA256(params, accessSecret);
  }

  String hmacSHA256(String data, String secret) {
    var key = utf8.encode(secret);
    var bytes = utf8.encode(data);
    var hmac = Hmac(sha256, key);
    var digest = hmac.convert(bytes);
    return digest.toString();
  }

}
