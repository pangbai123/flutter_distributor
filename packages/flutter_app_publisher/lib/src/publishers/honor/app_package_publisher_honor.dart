import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/doorzo/app_package_publisher_doorzo.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_app_publisher/src/publishers/util.dart';
import 'package:http/http.dart';

const kEnvHonorClientId = 'HONOR_CLIENT_ID';
const kEnvHonorAcessSecrt = 'HONOR_ACESS_SECRET';
const kEnvHonorAppId = 'HONOR_APP_ID';

///  doc [https://developer.honor.com/cn/doc/guides/101359]
class AppPackagePublisherHonor extends AppPackagePublisher {
  @override
  String get name => 'honor';

  String? token;
  String? access;
  String? client;
  String? greenId;
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
      client = globalEnvironment[kEnvHonorClientId];
      access = globalEnvironment[kEnvHonorAcessSecrt];
      if ((client ?? '').isEmpty) {
        throw PublishError('Missing `$kEnvHonorClientId` environment variable.');
      }
      if ((access ?? '').isEmpty) {
        throw PublishError(
            'Missing `$kEnvHonorAcessSecrt` environment variable.');
      }
      token = await getToken(client!, access!);
      await uploadApp(file, onPublishProgress);
      //更新日志
      await updateDesc();
      //提交审核信息
      await submit();
      return PublishResult(url: globalEnvironment[kEnvAppName]! + name + '提交成功}');
    }  catch (e) {
      print("app提交失败========$name$e=========");
      exit(1);
    }
  }

  Future submit({int times = 0}) async {
    await Future.delayed(Duration(seconds: 10));
    var map = await PublishUtil.sendRequest(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/submit-audit',
      {
        'testComment': '账号：nervzztc@hotmail.com\n密码：123456 \n 您好，由于通过api传包，测试账号会乱码，所以改为备注。',
        'releaseType': 1,
      },
      queryParams: {
        'appId': globalEnvironment[kEnvHonorAppId],
      },
      header: {
        'Authorization': 'Bearer ${token}',
      },
      isGet: false,
      isFrom: false,
    );
    if (map?['code'] == 0) {
      return;
    } else {
      print('重试提交$times');
      if (times == 10) throw PublishError("提交版本：${map}");
      await submit(times: times + 1);
    }
  }

  ///上传文件
  Future uploadApp(
    File file,
    PublishProgressCallback? onPublishProgress,
  ) async {
    Map? uploadMap;
    Digest sha256Result = sha256.convert(file.readAsBytesSync());
    String sha256Hash = sha256Result.toString();
    var map = await PublishUtil.sendRequest(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/get-file-upload-url',
      [
        {
          'fileName': file.path.split('/').last,
          'fileType': 100,
          'fileSize': await file.length(),
          'fileSha256': sha256Hash,
        }
      ],
      queryParams: {
        'appId': globalEnvironment[kEnvHonorAppId],
      },
      header: {
        'Authorization': 'Bearer ${token}',
      },
      isGet: false,
      isFrom: false,
    );
    if (map?["code"] == 0) {
      uploadMap = map!['data'][0];
    } else {
      throw PublishError("请求getUploadAppUrl失败：${map}");
    }
    //上传文件
    var request = MultipartRequest(
        'POST',
        Uri.parse(
          'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/file-upload?appId=${globalEnvironment[kEnvHonorAppId]}&objectId=${uploadMap?['objectId']}',
        ));
    request.headers['Authorization'] = 'Bearer ${token}';
    request.files.add(await MultipartFile.fromPath('file', file.path));
    var response = await request.send();
    if (response.statusCode != 200) {
      // 处理错误的响应
      throw PublishError("请求失败：${response.statusCode}");
    }
    String content = await response.stream.bytesToString();
    Map responseMap = jsonDecode(content);
    if (responseMap["code"] != 0) {
      throw PublishError(content);
    }
    //刷新文件信息
    var ret = await PublishUtil.sendRequest(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/update-file-info',
      {
        'bindingFileList': [
          {
            'objectId': uploadMap?['objectId'],
          }
        ],
      },
      queryParams: {
        'appId': globalEnvironment[kEnvHonorAppId],
      },
      header: {
        'Authorization': 'Bearer ${token}',
      },
      isGet: false,
      isFrom: false,
    );
    if (ret?['code'] == 0) {
    } else {
      throw PublishError("更新文件信息失败：${map}");
    }
  }

  Future updateDesc() async {
    try {
      var map = await PublishUtil.sendRequest(
        'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/get-app-detail',
        {},
        queryParams: {
          'appId': globalEnvironment[kEnvHonorAppId],
        },
        header: {
          'Authorization': 'Bearer ${token}',
        },
        isGet: true,
        isFrom: false,
      );
      if (map?["code"] != 0) {
        return;
      }
      var languageInfoList = map?['data']['languageInfo'];
      if (languageInfoList == null) return;
      (languageInfoList as List).forEach((element) {
        element['newFeature'] = globalEnvironment[kEnvUpdateLog];
      });
      await PublishUtil.sendRequest(
        'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/update-language-info',
        {'languageInfoList': languageInfoList},
        queryParams: {
          'appId': globalEnvironment[kEnvHonorAppId],
        },
        header: {
          'Authorization': 'Bearer ${token}',
        },
        isGet: true,
        isFrom: false,
      );
    } catch (e) {}
  }

  /// 获取上传 Token 信息
  Future<String> getToken(String client, String secret) async {
    var map = await PublishUtil.sendRequest(
      'https://iam.developer.honor.com/auth/token',
      {
        'grant_type': 'client_credentials',
        'client_id': client,
        'client_secret': secret,
      },
      isGet: false,
    );
    if (map?['access_token'] == null) {
      throw PublishError('getToken error: ${map}');
    }
    return map!['access_token'];
  }
}
