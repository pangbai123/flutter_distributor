import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/doorzo/app_package_publisher_doorzo.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_app_publisher/src/publishers/util.dart';
import 'package:http/http.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

const kEnvHuaweiClientId = 'HUAWEI_CLIENT_ID';
const kEnvHuaweiAcessSecrt = 'HUAWEI_ACESS_SECRET';
const kEnvHuaweiAppId = 'HUAWEI_APP_ID';
const kEnvHuaweiGreenFile = 'HUAWEI_GREEN_FILE';

///  doc [https://developer.huawei.com/consumer/cn/doc/AppGallery-connect-References/agcapi-obtain-token-project-0000001477336048]
class AppPackagePublisherHuawei extends AppPackagePublisher {
  @override
  String get name => 'huawei';

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
    await uploadApp(file, onPublishProgress);
    //上传绿色资料
    await uploadGreen();
    //更新日志
    await updateDesc();
    //提交审核信息
    await submit();
    return PublishResult(url: globalEnvironment[kEnvAppName]! + name + '提交成功}');
  }

  Future submit({int times = 0}) async {
    await Future.delayed(Duration(seconds: 10));
    var map = await PublishUtil.sendRequest(
      'https://connect-api.cloud.huawei.com/api/publish/v2/app-submit',
      {
        'isPureDetection': 1,
        'sensitivePermissionIconUrl': greenId,
        'isCommitSensitivePermissionTips': true,
      },
      queryParams: {
        'appId': globalEnvironment[kEnvHuaweiAppId],
        'releaseType': 1,
        'remark': '账号：nervzztc@hotmail.com\n密码：123456',
      },
      header: {
        'client_id': client,
        'Authorization': 'Bearer ${token}',
      },
      isGet: false,
      isFrom: false,
    );
    if (map?["ret"]['code'] == 0) {
      return;
    } else {
      print('重试提交$times');
      if (times == 30) throw PublishError("提交版本：${map}");
      await submit(times: times + 1);
    }
  }

  Future updateDesc() async {
    try {
      var map = await PublishUtil.sendRequest(
        'https://connect-api.cloud.huawei.com/api/publish/v2/app-info',
        {},
        queryParams: {
          'appId': globalEnvironment[kEnvHuaweiAppId],
        },
        header: {
          'client_id': client,
          'Authorization': 'Bearer ${token}',
        },
        isGet: true,
        isFrom: false,
      );
      if (map?["code"] != 0) {
        return;
      }
      var languageInfoList = map?['languages'];
      if (languageInfoList == null) return;
      if (languageInfoList is List) {
        for (var i = 0; i < languageInfoList.length; ++i) {
          var o = languageInfoList[i];
          await PublishUtil.sendRequest(
            'https://connect-api.cloud.huawei.com/api/publish/v2/app-language-info',
            {
              'lang': o['lang'],
              'appName': o['appName'],
              'appDesc': o['appDesc'],
              'briefInfo': o['briefInfo'],
              'newFeatures': globalEnvironment[kEnvUpdateLog],
            },
            queryParams: {
              'appId': globalEnvironment[kEnvHuaweiAppId],
            },
            header: {
              'client_id': client,
              'Authorization': 'Bearer ${token}',
            },
            isPut: true,
            isFrom: false,
          );
        }
      }
    } catch (e) {}
  }

  ///上传文件
  Future uploadApp(
    File file,
    PublishProgressCallback? onPublishProgress,
  ) async {
    Map? uploadMap;
    var map = await PublishUtil.sendRequest(
      'https://connect-api.cloud.huawei.com/api/publish/v2/upload-url/for-obs',
      {
        'appId': globalEnvironment[kEnvHuaweiAppId],
        'fileName': file.path.split('/').last,
        'contentLength': await file.length(),
      },
      header: {
        'client_id': client,
        'Authorization': 'Bearer ${token}',
      },
      isGet: true,
      isFrom: false,
    );
    if (map?["ret"]['code'] == 0) {
      uploadMap = map!['urlInfo'];
    } else {
      throw PublishError("请求getUploadAppUrl失败：${map}");
    }
    var response = await put(
      Uri.parse(uploadMap!['url']),
      body: file.readAsBytesSync(),
      headers: (uploadMap['headers'] as Map).cast<String, String>(),
    );
    if (response.statusCode == 200) {
      String content = await response.body;
      print('文件上传成功：$content');
      //刷新文件信息
      var map = await PublishUtil.sendRequest(
        'https://connect-api.cloud.huawei.com/api/publish/v2/app-file-info',
        {
          'fileType': 5,
          'files': [
            {
              'fileName': file.path.split('/').last,
              'fileDestUrl': uploadMap['objectId'],
            }
          ],
        },
        queryParams: {
          'appId': globalEnvironment[kEnvHuaweiAppId],
          'releaseType': 1,
        },
        header: {
          'client_id': client,
          'Authorization': 'Bearer ${token}',
        },
        isGet: false,
        isFrom: false,
        isPut: true,
      );
      if (map?["ret"]['code'] == 0) {
        return;
      } else {
        throw PublishError("更新文件信息失败：${map}");
      }
    } else {
      // 处理错误的响应
      throw PublishError("请求失败：${response.statusCode}");
    }
  }

  ///上传文件
  Future uploadGreen() async {
    var file = File(globalEnvironment[kEnvHuaweiGreenFile]!);
    Map? uploadMap;
    var map = await PublishUtil.sendRequest(
      'https://connect-api.cloud.huawei.com/api/publish/v2/upload-url/for-obs',
      {
        'appId': globalEnvironment[kEnvHuaweiAppId],
        'fileName': file.path.split('/').last,
        'contentLength': await file.length(),
      },
      header: {
        'client_id': client,
        'Authorization': 'Bearer ${token}',
      },
      isGet: true,
      isFrom: false,
    );
    if (map?["ret"]['code'] == 0) {
      uploadMap = map!['urlInfo'];
    } else {
      throw PublishError("请求getUploadAppUrl失败：${map}");
    }
    var response = await put(
      Uri.parse(uploadMap!['url']),
      body: file.readAsBytesSync(),
      headers: (uploadMap['headers'] as Map).cast<String, String>(),
    );
    if (response.statusCode == 200) {
      String content = await response.body;
      print('文件上传成功：$content');
      greenId = uploadMap['objectId'];
    } else {
      // 处理错误的响应
      throw PublishError("请求失败：${response.statusCode}");
    }
  }

  /// 获取上传 Token 信息
  Future<String> getToken(String client, String secret) async {
    var map = await PublishUtil.sendRequest(
      'https://connect-api.cloud.huawei.com/api/oauth2/v1/token',
      {
        'grant_type': 'client_credentials',
        'client_id': client,
        'client_secret': secret,
      },
      isGet: false,
      isFrom: false,
    );
    if (map?['access_token'] == null) {
      throw PublishError('getToken error: ${map}');
    }
    return map!['access_token'];
  }
}
