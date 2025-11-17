import 'dart:async';
import 'dart:io';

import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_app_publisher/src/publishers/util.dart';
import 'package:http/http.dart';

const kEnvHuaweiClientId = 'HUAWEI_CLIENT_ID';
const kEnvHuaweiAcessSecrt = 'HUAWEI_ACESS_SECRET';
const kEnvHuaweiAppId = 'HUAWEI_APP_HMOS_ID';
const kEnvHuaweiGreenFile = 'HUAWEI_GREEN_FILE';

///  doc https://developer.huawei.com/consumer/cn/doc/AppGallery-connect-References/agcapi-publishingapi-harmonyos-0000002093065194
class AppPackagePublisherHmos extends AppPackagePublisher {
  @override
  String get name => 'hmos';

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
      client = globalEnvironment[kEnvHuaweiClientId];
      access = globalEnvironment[kEnvHuaweiAcessSecrt];
      if ((client ?? '').isEmpty) {
        throw PublishError(
            'Missing `$kEnvHuaweiClientId` environment variable.');
      }
      if ((access ?? '').isEmpty) {
        throw PublishError(
            'Missing `$kEnvHuaweiAcessSecrt` environment variable.');
      }
      token = await getToken(client!, access!);
      await uploadApp(file, onPublishProgress);

      Map appInfo = await getAppInfo();
      //上传绿色资料
      // await uploadGreen();
      //更新日志
      await updateDesc(appInfo);
      //提交审核信息
      await submit();
      return PublishResult(
          url: globalEnvironment[kEnvAppName]! + name + '提交成功}');
    }  catch (e) {
      exit(1);
    }
  }

  Future submit({int times = 0}) async {
    await Future.delayed(Duration(seconds: 10));
    var map = await PublishUtil.sendRequest(
      'https://connect-api.cloud.huawei.com/api/publish/v3/app-submit',
      {
        'remark': '账号：nervzztc@hotmail.com\n密码：123456',
      },
      queryParams: {
        'appId': globalEnvironment[kEnvHuaweiAppId],
      },
      header: {
        'client_id': client,
        'Authorization': 'Bearer ${token}',
      },
      isGet: false,
      isFrom: false,
    );
    if (map?['ret']['code'] == 0) {
      return;
    } else {
      print('重试提交$times');
      if (times == 30) throw PublishError('提交版本：${map}');
      await submit(times: times + 1);
    }
  }

  Future getAppInfo() async {
    var map = await PublishUtil.sendRequest(
      'https://connect-api.cloud.huawei.com/api/publish/v3/app-info',
      {
        'appId': globalEnvironment[kEnvHuaweiAppId],
      },
      header: {
        'client_id': client,
        'Authorization': 'Bearer ${token}',
      },
      isGet: true,
      isFrom: false,
      isPut: false,
    );
    return map['appInfo'];
  }

  Future updateDesc(Map appInfo) async {
    String publishCountry = appInfo['publishCountry'];
    try {
      var map = await PublishUtil.sendRequest(
        'https://connect-api.cloud.huawei.com/api/publish/v3/app-info',
        {'publishCountry': publishCountry, 'encrypted': 0},
        queryParams: {
          'appId': globalEnvironment[kEnvHuaweiAppId],
        },
        header: {
          'client_id': client,
          'Authorization': 'Bearer ${token}',
        },
        isGet: false,
        isFrom: false,
        isPut: true,
      );
      print('!!!!!!!${map}!!!!!!!!');
      if (map?['ret']['code'] != 0) {
        return;
      }
      if (appInfo == null) {
        return;
      }
      var desMap = await PublishUtil.sendRequest(
          'https://connect-api.cloud.huawei.com/api/publish/v3/app-language-info',
          {
            'lang': appInfo['defaultLang'],
            'newFeatures': globalEnvironment[kEnvUpdateLog],
            'appId': globalEnvironment[kEnvHuaweiAppId],
          },
          queryParams: {
            'lang': appInfo['defaultLang'],
            'newFeatures': globalEnvironment[kEnvUpdateLog],
            'appId': globalEnvironment[kEnvHuaweiAppId],
          },
          header: {
            'client_id': client,
            'Authorization': 'Bearer ${token}',
          },
          isGet: false,
          isPut: true,
          isFrom: false);
      if (desMap['ret']?['code'] != 0) {
        throw PublishError('更新应用信息失败（更新信息');
      }
    } catch (e) {
      print('aaaa=======$e========');
    }
  }

  ///上传文件（获取文件上传地址
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
    if (map?['ret']['code'] == 0) {
      uploadMap = map!['urlInfo'];
    } else {
      throw PublishError('请求getUploadAppUrl失败：${map}');
    }
    var response = await put(
      Uri.parse(uploadMap!['url']),
      body: file.readAsBytesSync(),
      headers: (uploadMap['headers'] as Map).cast<String, String>(),
    );

    if (response.statusCode == 200) {
      if (map?['ret']['code'] == 0) {
        var map = await PublishUtil.sendRequest(
          'https://connect-api.cloud.huawei.com/api/publish/v3/app-package-info',
          {
            'fileName': file.path.split('/').last,
            'objectId': uploadMap['objectId'],
          },
          queryParams: {
            'appId': globalEnvironment[kEnvHuaweiAppId],
          },
          header: {
            'client_id': client,
            'Authorization': 'Bearer ${token}',
          },
          isGet: false,
          isFrom: false,
          isPut: true,
        );
        if (map?['ret']['code'] == 0) {
          return;
        } else {
          throw PublishError('更新文件信息失败：${map}');
        }
      } else {
        throw PublishError('bbbb更新文件信息失败：${map}');
      }
    } else {
      throw PublishError('请求失败：${response.statusCode}');
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
