import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';

const kEnvClientIdApi = 'OPPO_CLIENT_ID';
const kEnvAccessSecretApi = 'OPPO_ACCESS_SECRET';

///  doc [https://open.oppomobile.com/new/developmentDoc/info?id=10998]
class AppPackagePublisherOppo extends AppPackagePublisher {
  @override
  String get name => 'oppo';

  // dio 网络请求实例
  final Dio _dio = Dio();

  // 轮询尝试次数
  int tryCount = 0;

  // 最大尝试轮询次数
  final maxTryCount = 10;
  String? client;
  String? access;

  @override
  Future<PublishResult> publish(
    FileSystemEntity fileSystemEntity, {
    Map<String, String>? environment,
    Map<String, dynamic>? publishArguments,
    PublishProgressCallback? onPublishProgress,
  }) async {
    File file = fileSystemEntity as File;
    client = (environment ?? Platform.environment)[kEnvClientIdApi];
    access = (environment ?? Platform.environment)[kEnvAccessSecretApi];
    if ((client ?? '').isEmpty) {
      throw PublishError('Missing `$kEnvClientIdApi` environment variable.');
    }
    if ((access ?? '').isEmpty) {
      throw PublishError(
          'Missing `$kEnvAccessSecretApi` environment variable.');
    }
    Map? map = await getUploadAppUrl(client!, access!);
    if (map == null) {
      throw PublishError('getUploadAppUrl error');
    }
    String url = map["data"]["upload_url"];
    String sign = map["data"]["sign"];
    Map uploadInfo = await uploadApp(url, sign, file, onPublishProgress);

    //{"errno":0,"data":{"url":"http://storedl1.nearme.com.cn/apk/tmp_apk/202405/08/1829dba19eb6451d9472669d0caac007.apk",
    // "uri_path":"/apk/tmp_apk/202405/08/1829dba19eb6451d9472669d0caac007.apk","md5":"fc43371e8e57ec2b0fa87c316b52bb89",
    // "file_size":36028706,"file_extension":"apk","width":0,"height":0,"id":"5db79aa7-5790-4a4a-9188-84b2d455ccd2",
    // "sign":"49f5785281fa2669c9251152fa73dcb8"},"logid":"5db79aa7-5790-4a4a-9188-84b2d455ccd2"}

    // 重试次数设置为 0
    tryCount = 0;
    // var buildResult = await getBuildInfo(apiKey, uploadKey);
    // String buildKey = buildResult.data!['data']['buildKey'];
    return PublishResult(
      url: '${jsonEncode(uploadInfo)}',
    );
  }

//{
//         "url": "https://oppo.com/********261d.apk",
//         "uri_path": "/********261d.apk",
//         "md5": "5efd****4d4d",
//         "file_extension": "apk",
//         "file_size": 4181241,
//         "id": "XXXXX"
//     }
  //
  Future<Map> uploadApp(
    String url,
    String sign,
    File file,
    PublishProgressCallback? onPublishProgress,
  ) async {
    List<int> fileBytes = await file.readAsBytes();

    Map<String, dynamic> params = {
      'access_token': await getToken(client!, access!),
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'type': 'apk',
      'sign': sign,
      "file": fileBytes,
    };

    String api_sign = signRequest(access!, params);
    params['api_sign'] = api_sign;
    String? content = await uploadFile(url, sign, 'apk', file);
    if (content == null) {
      throw PublishError('uploadFile erro');
    }
    Map responseMap = jsonDecode(content);
    if (responseMap["errno"] == 0) {
      return responseMap;
    } else {
      throw PublishError(content);
    }
  }

  Future<String?> uploadFile(
      String uploadUrl, String sign, String type, File file) async {
    var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    request.fields['type'] = type;
    request.fields['sign'] = sign;
    request.fields['access_token'] = await getToken(client!, access!) ?? "";
    request.fields['timestamp'] =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    var response = await request.send();
    if (response.statusCode == 200) {
      String content = await response.stream.bytesToString();
      return content;
    } else {
      // 处理错误的响应
      throw PublishError("请求失败：${response.statusCode}");
    }
  }

  Future<Map?> getUploadAppUrl(String client, String secret) async {
    Map<String, dynamic> params = {
      'access_token': await getToken(client, secret),
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };
    String sign = signRequest(secret, params);
    params['api_sign'] = sign;
    String content = await sendRequest(
        'https://oop-openapi-cn.heytapmobi.com/resource/v1/upload/get-upload-url',
        params);
    if (content.isEmpty) {
      throw PublishError("=====请求getUploadAppUrl失败=====");
    }
    Map map = jsonDecode(content);
    if (map["errno"] == 0) {
      return map;
    } else {
      throw PublishError("=====请求getUploadAppUrl失败=====");
    }
  }

  /// 获取上传 Token 信息
  /// [apiKey] apiKey
  /// [filePath] 文件路径
  Future<String> getToken(String client, String secret) async {
    try {
      Response response = await _dio.get(
        'https://oop-openapi-cn.heytapmobi.com/developer/v1/token',
        queryParameters: {
          'client_id': client,
          'client_secret': secret,
        },
      );
      if (response.data?['data']?['access_token'] == null) {
        throw PublishError('getToken error: ${response.data}');
      }
      return response.data['data']['access_token'];
    } catch (e) {
      throw PublishError(e.toString());
    }
  }

  /// 获取应用发布构建信息
  /// [apiKey] apiKey
  /// [uploadKey] uploadKey
  Future<Response> getBuildInfo(String apiKey, String uploadKey) async {
    if (tryCount > maxTryCount) {
      throw PublishError('getBuildInfo error :Too many retries');
    }
    await Future.delayed(const Duration(seconds: 3));
    try {
      Response response = await _dio.get(
        'https://www.pgyer.com/apiv2/app/buildInfo',
        queryParameters: {
          '_api_key': apiKey,
          'buildKey': uploadKey,
        },
      );
      int code = response.data['code'];
      if (code == 1247) {
        tryCount++;
        print('应用发布信息获取中，请稍等 $tryCount');
        return await getBuildInfo(apiKey, uploadKey);
      } else if (code != 0) {
        throw PublishError('getBuildInfo error: ${response.data}');
      }
      return response;
    } catch (e) {
      throw PublishError(e.toString());
    }
  }

  Future<String> sendRequest(String requestUrl, Map<String, dynamic> params,
      {bool isGet = true}) async {
    Uri uri = Uri.parse('$requestUrl?${buildQuery(params)}');
    Response<String> response;
    if (isGet) {
      Uri uri = Uri.parse('$requestUrl?${buildQuery(params)}');
      response = await _dio.get<String>(uri.toString());
    } else {
      response = await _dio.post<String>(
        uri.toString(),
        data: params,
      );
    }
    if ((response.statusCode ?? 0) >= 400) {
      throw Exception('${response.statusCode} ${response.data}');
    }
    return response.data ?? '';
  }

  String buildQuery(Map<String, dynamic> params, {String charset = 'utf-8'}) {
    List<String> query = [];
    params.forEach((key, value) {
      if (value != null) {
        query.add('$key=${Uri.encodeQueryComponent(value.toString())}');
      }
    });
    return query.join('&');
  }

  String signRequest(String secret, Map<String, dynamic> paramsMap) {
    List<String> keysList = paramsMap.keys.toList()..sort();
    List<String> paramList = [];
    for (String key in keysList) {
      dynamic object = paramsMap[key];
      if (object == null) continue;
      String value = '$key=$object';
      paramList.add(value);
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
