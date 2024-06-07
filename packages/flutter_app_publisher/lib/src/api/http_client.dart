import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

enum Method { get, post, delete }

typedef Success<T> = void Function(T? entity);
typedef Error = void Function(HttpException exception);
typedef HandleData = void Function(Map<String, dynamic>? ret);
typedef Result = void Function(Map<String, dynamic>? ret);

class HttpException implements Exception {
  final String? msg;
  final String code;

  ///是否本地错误
  final bool isLocal;
  final dynamic data;

  const HttpException(this.code, this.msg, {this.isLocal = false, this.data});
}

class DoorzoHttpClient {
  ///测试平台
  static String platformUrl0 = 'https://dev.doorzo.net/';

  ///生产平台
  static String platformUrl1 = 'https://sig.binpom.com/';

  ///是否测试平台
  static bool isTest = false;
  static String baseUrl = platformUrl1;

  factory DoorzoHttpClient() => _getInstance();

  static DoorzoHttpClient get instance => _getInstance();
  static DoorzoHttpClient? _instance;
  static int connectTime = 10;
  static int reciveTime = 30;

  DioMixin? dio;
  PersistCookieJar? cookieJar;
  CookieManager? cookieManager;

  static DoorzoHttpClient _getInstance() {
    if (_instance == null) {
      _instance = DoorzoHttpClient._internal();
    }
    return _instance!;
  }

  DoorzoHttpClient._internal();

  Future<void> init() async {
    // 初始化
    if (isTest) {
      baseUrl = platformUrl0;
    } else {
      baseUrl = platformUrl1;
    }
    //重新初始化
    dio = DioForNative(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout:
          isTest ? const Duration(seconds: 30) : Duration(seconds: connectTime),
      receiveTimeout: Duration(seconds: reciveTime),
    ));
    cookieJar = PersistCookieJar();
    await cookieJar!.deleteAll();
    cookieManager = CookieManager(cookieJar!);

    dio!.interceptors.add(cookieManager!);
    dio!.interceptors.add(PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseHeader: true,
        maxWidth: 600));
  }

  Future<T?> syncRequest<T>(Map<String, dynamic> param,
      {String url = '',
      bool isGet = true,
      Map<String, dynamic>? urlParams}) async {
    if (dio == null) {
      await init();
    }
    var params = <String, dynamic>{};
    params.addAll(param);

    if (isGet) {
      params['from'] = 'win';
    } else {
      if (url.contains('?')) {
        url += '&from=win';
      } else {
        url += '?from=win';
      }

      if (params.containsKey('n')) {
        url += '&n=' + params['n'];
        params.remove('n');
      }
      if (urlParams == null) {
        urlParams = {};
      }
      urlParams.forEach((key, value) {
        url += '&$key=$value';
      });
    }
    var method = isGet ? Method.get : Method.post;
    Response<String>? response;
    try {
      switch (method) {
        case Method.get:
          response = await dio!.get<String>(url, queryParameters: params);
          break;
        case Method.post:
          response = await dio!.post<String>(url, data: params);
          break;
        case Method.delete:
          break;
      }
    } catch (exception) {
      print('错误：$url,${exception.toString()}');
    }
    if (response?.statusCode == 401) {
      throw const HttpException("-1", "已注销");
    }
    if (response == null || response.statusCode! >= 400) {
      throw const HttpException("-1", "网络无法连接，请稍后重试");
    }

    //线程池
    Map para = {
      'data': response.data,
      'type': T.toString(),
    };
    return parseJson2Map(para);
  }
}

///解析json 顶级函数
parseJson2Map(Map map) {
  var ret = json.decode(map['data']);
  var type = map['type'];
  print(type);
  var src = ret['data'];
  if (ret['code'] == 200) {
    if (type.startsWith('Map') ||
        type == 'Object' ||
        type == 'double' ||
        type == 'int' ||
        type == 'dynamic' ||
        type == 'bool') {
      return src;
    } else if (type.startsWith('String')) {
      return src?.toString();
    } else if (type.startsWith('List<String>')) {
      return (src as List).cast<String>();
    }
  }
  throw HttpException("-1", "解析出错");
}
