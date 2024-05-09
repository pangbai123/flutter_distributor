import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

const kEnvVivoKey = 'VIVO_ACCESS_KEY';
const kEnvVivoSecret = 'VIVO_ACCESS_SECRET';

///  doc [https://dev.vivo.com.cn/documentCenter/doc/326]
class AppPackagePublisherVivo extends AppPackagePublisher {
  @override
  String get name => 'vivo';

  // dio 网络请求实例
  final Dio _dio = Dio(BaseOptions(
      connectTimeout: Duration(seconds: 15),
      receiveTimeout: Duration(seconds: 60)))
    ..interceptors.add(PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseHeader: true,
        maxWidth: 600));
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
    print('上传文件成功：${jsonEncode(uploadInfo)}');
    // //提交审核信息
    Map submitInfo = await submit(uploadInfo, {});
    return PublishResult(
      url: 'vivo提交成功：${jsonEncode(submitInfo)}',
    );
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
    params['sign'] = signRequest(access!, params);
    String content = await sendRequest(
        'https://developer-api.vivo.com.cn/router/rest', params,
        isGet: false);
    if (content.isEmpty) {
      throw PublishError("请求submit失败：$content");
    }
    Map map = jsonDecode(content);
    if (map["code"] == 0) {
      return map;
    } else {
      throw PublishError("请求submit失败：$content");
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
    request.fields['sign'] = signRequest(access!, request.fields);
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

  Future<String> sendRequest(String requestUrl, Map<String, dynamic> params,
      {Map<String, dynamic>? queryParams, bool isGet = true}) async {
    Response<String> response;
    try {
      if (isGet) {
        response = await _dio.get<String>(requestUrl, queryParameters: params);
      } else {
        _dio.options.contentType = Headers.formUrlEncodedContentType;
        response = await _dio.post<String>(requestUrl,
            data: params, queryParameters: queryParams);
      }
    } catch (e) {
      if (e is DioException) {
        throw Exception('${e.type} ${e.message}');
      }
      throw Exception('${e.toString()} ');
    }
    if ((response.statusCode ?? 0) >= 400) {
      throw Exception('${response.statusCode} ${response.data}');
    }
    return response.data ?? '';
  }

  String signRequest(String secret, Map<String, dynamic> paramsMap) {
    List<String> keysList = paramsMap.keys.toList()..sort();
    List<String> paramList = [];
    for (String key in keysList) {
      dynamic object = paramsMap[key];
      if (object == null) continue;
      if (object is List || object is Map) {
        paramList.add('$key=${jsonEncode(object)}');
      } else {
        paramList.add('$key=$object');
      }
    }
    String signStr = paramList.join('&');
    return hmacSHA256(signStr, secret);
  }

  String hmacSHA256(String data, String key) {
    List<int> secretByte = utf8.encode(key);
    var hmacSha256 = Hmac(sha256, secretByte);
    List<int> dataByte = utf8.encode(data);
    Digest digest = hmacSha256.convert(dataByte);
    return digest.toString();
  }
}
