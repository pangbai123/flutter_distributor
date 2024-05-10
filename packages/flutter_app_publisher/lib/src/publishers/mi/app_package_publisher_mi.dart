import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt_io.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asymmetric/api.dart';

const kEnvMiAccount = 'MI_ACCOUNT';
const kEnvMiCer = 'MI_CER';
const kEnvMiPrivateKey = 'MI_PRIVATE_KEY';
const kEnvAppName = 'APP_NAME';
const kEnvPrivacyUrl = 'PRIVACY_URL';

///  doc [https://dev.mi.com/distribute/doc/details?pId=1134]
class AppPackagePublisherMi extends AppPackagePublisher {
  @override
  String get name => 'mi';

  // dio 网络请求实例
  final Dio _dio = Dio(BaseOptions(
      connectTimeout: Duration(seconds: 15),
      receiveTimeout: Duration(seconds: 60)))
    ..interceptors.add(PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseHeader: true,
        maxWidth: 600));
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
    Map uploadInfo = await uploadApp(
        globalEnvironment[kEnvPkgName]!, file, onPublishProgress);
    return PublishResult(
      url: 'mi提交成功：${jsonEncode(uploadInfo)}',
    );
  }

  ///上传文件
  Future<Map> uploadApp(
    String pkg,
    File file,
    PublishProgressCallback? onPublishProgress,
  ) async {
    var request = http.MultipartRequest('POST',
        Uri.parse('https://api.developer.xiaomi.com/devupload/dev/push'));
    var appInfo = <String, dynamic>{
      'appName': globalEnvironment[kEnvAppName],
      'packageName': globalEnvironment[kEnvPkgName],
      'updateDesc': globalEnvironment[kEnvUpdateLog],
      'privacyUrl': globalEnvironment[kEnvPrivacyUrl],
      'testAccount':
          jsonEncode({"zh_CN": "账号：nervzztc@hotmail.com\n密码：123456"}),
    };
    var RequestData = <String, dynamic>{
      'userName': globalEnvironment[kEnvMiAccount],
      'synchroType': 1,
      'appInfo': jsonEncode(appInfo),
    };
    request.fields['RequestData'] = jsonEncode(RequestData);

    request.files.add(await http.MultipartFile.fromPath('apk', file.path));

    var arr = {
      "sig": [
        {
          "name": "RequestData",
          "hash": md5
              .convert(utf8.encode(request.fields['RequestData']!))
              .toString()
              .toLowerCase()
        },
        {
          "name": "apk",
          "hash": md5.convert(file.readAsBytesSync()).toString().toLowerCase()
        },
      ],
      "password": globalEnvironment[kEnvMiPrivateKey]
    };
    print(File(globalEnvironment[kEnvMiCer]!).readAsStringSync());
    final publicKey =
        await parseKeyFromFile<RSAPublicKey>(globalEnvironment[kEnvMiCer]!);
    final privateKey = RSAKeyParser()
        .parse(globalEnvironment[kEnvMiPrivateKey]!) as RSAPrivateKey;
    var encrypter = Encrypter(
      RSA(
          publicKey: publicKey,
          privateKey: privateKey,
          encoding: RSAEncoding.PKCS1),
    );
    var encrypted = encrypter.encrypt(jsonEncode(arr));

    request.fields['SIG'] = encrypted.base64;
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
