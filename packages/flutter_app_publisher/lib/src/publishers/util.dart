import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

class PublishUtil {
  // dio 网络请求实例
  static final Dio _dio = Dio(BaseOptions(
      connectTimeout: Duration(seconds: 60),
      receiveTimeout: Duration(seconds: 60)))
    ..interceptors.add(PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseHeader: true,
        maxWidth: 600));

  static Future<dynamic> sendRequest(
    String requestUrl,
    dynamic params, {
    Map<String, dynamic>? header,
    Map<String, dynamic>? queryParams,
    bool isGet = true,
    bool isFrom = true,
    bool isPut = false,
  }) async {
    Response response;
    if (isFrom) {
      _dio.options.contentType = Headers.formUrlEncodedContentType;
    } else {
      _dio.options.contentType = Headers.jsonContentType;
    }
    try {
      if (isGet) {
        response = await _dio.get<String>(requestUrl,
            queryParameters: params, options: Options()..headers = header);
      } else if (isPut) {
        response = await _dio.put<String>(requestUrl,
            data: params,
            queryParameters: queryParams,
            options: Options()..headers = header);
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
    if (response.data == null) {
      return null;
    }
    return jsonDecode(response.data);
  }

  static String oppoSign(String secret, Map<String, dynamic> paramsMap) {
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

  static String hmacSHA256(String data, String key) {
    List<int> secretByte = utf8.encode(key);
    var hmacSha256 = Hmac(sha256, secretByte);
    List<int> dataByte = utf8.encode(data);
    Digest digest = hmacSha256.convert(dataByte);
    return digest.toString();
  }

  static String bytesToHex(List<int> bytes) {
    StringBuffer hexStr = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      String hex = bytes[i].toRadixString(16);
      hexStr.write('${hex.length == 1 ? '0' + hex : hex}');
    }
    return hexStr.toString();
  }
}
