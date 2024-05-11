import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

const kEnvHuaweiClientId = 'HUAWEI_CLIENT_ID';
const kEnvHuaweiAcessSecrt = 'HUAWEI_ACESS_SECRET';
const kEnvHuaweiAppId = 'HUAWEI_APP_ID';

///  doc [https://developer.huawei.com/consumer/cn/doc/AppGallery-connect-References/agcapi-obtain-token-project-0000001477336048]
class AppPackagePublisherHuawei extends AppPackagePublisher {
  @override
  String get name => 'huawei';

  // dio 网络请求实例
  final Dio _dio = Dio(BaseOptions(
      connectTimeout: Duration(seconds: 15),
      receiveTimeout: Duration(seconds: 60)))
    ..interceptors.add(PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseHeader: true,
        maxWidth: 600));
  String? token;
  String? access;
  String? client;
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
    client = globalEnvironment[kEnvHuaweiClientId];
    access = globalEnvironment[kEnvHuaweiAcessSecrt];
    if ((client ?? '').isEmpty) {
      throw PublishError('Missing `$kEnvHuaweiClientId` environment variable.');
    }
    if ((access ?? '').isEmpty) {
      throw PublishError(
          'Missing `$kEnvHuaweiAcessSecrt` environment variable.');
    }
    token = await getToken(client!, access!);
    Map? map = await getUploadAppUrl(file);
    print('获取上传地址成功：${jsonEncode(map)}');
    if (map == null) {
      throw PublishError('getUploadAppUrl error');
    }
    // String url = map["data"]["upload_url"];
    // String sign = map["data"]["sign"];
    // Map uploadInfo = await uploadApp(url, sign, file, onPublishProgress);
    // print('上传文件成功：${jsonEncode(uploadInfo)}');
    // //获取应用信息
    // Map appInfo = await getAppInfo(globalEnvironment[kEnvPkgName]!);
    // print('获取应用信息成功：${jsonEncode(appInfo)}');
    // //提交审核信息
    // Map submitInfo = await submit(uploadInfo, appInfo);
    return PublishResult(
      url: 'oppo提交成功：${jsonEncode('submitInfo')}',
    );
  }

  Future<Map?> submit(Map uploadInfo, Map appInfo) async {
    // Map<String, dynamic> data = appInfo['data'].cast<String, dynamic>();
    // Map<String, dynamic> params = {};
    // params['pkg_name'] = data['pkg_name'];
    // params['version_code'] = globalEnvironment[kEnvVersionCode];
    // params['apk_url'] = [
    //   {
    //     'url': uploadInfo['data']['url'],
    //     'md5': uploadInfo['data']['md5'],
    //     'cpu_code': 0,
    //   }
    // ];
    // params['app_name'] = data['app_name'];
    // params['app_subname'] = data['app_subname'];
    // params['second_category_id'] = data['second_category_id'];
    // params['third_category_id'] = data['third_category_id'];
    // params['summary'] = data['summary'];
    // params['detail_desc'] = data['detail_desc'];
    // params['update_desc'] = globalEnvironment[kEnvUpdateLog];
    // params['privacy_source_url'] = data['privacy_source_url'];
    // params['icon_url'] = data['icon_url'];
    // params['pic_url'] = data['pic_url'];
    // params['landscape_pic_url'] = data['landscape_pic_url'];
    // params['online_type'] = 1;
    // params['test_desc'] = data['test_desc'];
    // params['electronic_cert_url'] = data['electronic_cert_url'];
    // params['copyright_url'] = data['copyright_url'];
    // params['icp_url'] = data['icp_url'];
    // params['special_url'] = data['special_url'];
    // params['special_file_url'] = data['special_file_url'];
    // params['business_username'] = data['business_username'];
    // params['business_email'] = data['business_email'];
    // params['business_mobile'] = data['business_mobile'];
    // params['age_level'] = data['age_level'];
    // params['adaptive_equipment'] = data['adaptive_equipment'];
    // params['adaptive_type'] = 1;
    //
    // params['access_token'] = token!;
    // params['timestamp'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    //
    // params.removeWhere((key, value) => value == null);
    //
    // params = params.map((key, value) {
    //   if (value is List || value is Map) {
    //     return MapEntry(key, jsonEncode(value));
    //   } else {
    //     return MapEntry(key, value);
    //   }
    // });
    // params['api_sign'] = signRequest(access!, params);
    // String content = await sendRequest(
    //     'https://oop-openapi-cn.heytapmobi.com/resource/v1/app/upd', params,
    //     isGet: false);
    // if (content.isEmpty) {
    //   throw PublishError("请求submit失败：$content");
    // }
    // Map map = jsonDecode(content);
    // if (map["errno"] == 0) {
    //   return map;
    // } else {
    //   throw PublishError("请求submit失败：$content");
    // }
  }

  ///获取信息
  Future<Map?> getAppInfo(String pkg_name) async {
    // Map<String, dynamic> params = {
    //   'access_token': token!,
    //   'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    //   'pkg_name': pkg_name,
    // };
    // String sign = signRequest(access!, params);
    // params['api_sign'] = sign;
    // String content = await sendRequest(
    //     'https://oop-openapi-cn.heytapmobi.com/resource/v1/app/info', params);
    // if (content.isEmpty) {
    //   throw PublishError("请求getAppInfo失败：$content");
    // }
    // Map map = jsonDecode(content);
    // if (map["errno"] == 0) {
    //   return map;
    // } else {
    //   throw PublishError("请求getAppInfo失败：$content");
    // }
  }

  ///上传文件
  Future<Map> uploadApp(
    String url,
    String sign,
    File file,
    PublishProgressCallback? onPublishProgress,
  ) async {
    var request = http.MultipartRequest('POST', Uri.parse(url));
    request.fields['type'] = 'apk';
    request.fields['sign'] = sign;
    request.fields['access_token'] = token!;
    request.fields['timestamp'] =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    var response = await request.send();
    if (response.statusCode == 200) {
      String content = await response.stream.bytesToString();
      Map responseMap = jsonDecode(content);
      if (responseMap["errno"] == 0) {
        return responseMap;
      } else {
        throw PublishError(content);
      }
    } else {
      // 处理错误的响应
      throw PublishError("请求失败：${response.statusCode}");
    }
  }

  Future<Map?> getUploadAppUrl(File file) async {
    Response response = await sendRequest(
        'https://connect-api.cloud.huawei.com/api/publish/v2/upload-url/for-obs',
        {
          'appId': globalEnvironment[kEnvHuaweiAppId],
          'fileName': file.path,
          'contentLength': await file.length(),
        },
        header: {
          'client_id': client,
          'Authorization': 'Authorization: Bearer ${token}',
        },
        isGet: false);
    if (response.data == null) {
      throw PublishError("请求getUploadAppUrl失败：${response.data}");
    }
    Map map = jsonDecode(response.data);
    if (map["ret"]['code'] == 0) {
      return map['urlInfo'];
    } else {
      throw PublishError("请求getUploadAppUrl失败：${response.data}");
    }
  }

  /// 获取上传 Token 信息
  Future<String> getToken(String client, String secret) async {
    Response response = await sendRequest(
        'https://connect-api.cloud.huawei.com/api/oauth2/v1/token',
        {
          'grant_type': 'client_credentials',
          'client_id': client,
          'client_secret': secret,
        },
        isGet: false);
    if (response.data?['access_token'] == null) {
      throw PublishError('getToken error: ${response.data}');
    }
    return response.data['access_token'];
  }

  Future<Response> sendRequest(String requestUrl, Map<String, dynamic> params,
      {Map<String, dynamic>? header,
      Map<String, dynamic>? queryParams,
      bool isGet = true}) async {
    Response response;
    try {
      if (isGet) {
        response = await _dio.get<String>(requestUrl,
            queryParameters: params, options: Options()..headers = header);
      } else {

        response = await _dio.post<String>(requestUrl,
            data: params,
            queryParameters: queryParams,
            options: Options()..headers = header);
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
    return response;
  }
}
