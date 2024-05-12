import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_oss_aliyun/flutter_oss_aliyun.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

const kEnvDoorzoOssInfo = 'DOORZO_OSS_INFO';

class AppPackagePublisherDoorzo extends AppPackagePublisher {
  @override
  String get name => 'doorzo';

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
    var url = await uploadApp(file, onPublishProgress);
    print('上传文件成功：${url}');
    await submit(url);
    return PublishResult(url: globalEnvironment[kEnvAppName]! + name + '提交成功}');
  }

  Future submit(String url) async {
    //修改我们后台版本信息
    Map<String, dynamic> params = {};
    params['adaptive_type'] = 1;
    //
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

  ///上传文件到阿里云
  Future<String> uploadApp(
    File file,
    PublishProgressCallback? onPublishProgress,
  ) async {
    var info = globalEnvironment[kEnvDoorzoOssInfo]!.split('_');
    Client.init(
      ossEndpoint: info[0],
      bucketName: info[1],
      authGetter: () async {
        return Auth(
          accessKey: info[3],
          accessSecret: info[4],
          expire: DateTime.now().add(Duration(hours: 1)).toIso8601String(),
          secureToken: '',
        );
      },
    );

    var key = info[2] +
        '/' +
        globalEnvironment[kEnvModuleName]! +
        '_' +
        globalEnvironment[kEnvVersionName]! +
        '.apk';
    var ret = await Client().putObjectFile(
      file.path,
      fileKey: key,
      option: PutRequestOption(
        onSendProgress: (count, total) {
          onPublishProgress?.call(count, total);
        },
        override: true,
        aclModel: AclMode.publicRead,
        storageType: StorageType.standard,
        headers: {"cache-control": "no-cache"},
      ),
    );
    //再上传一个到做广告里
    await Client().copyObject(CopyRequestOption(
        sourceFileKey: key,
        targetFileKey: 'publish/' + globalEnvironment[kEnvModuleName]! + '.apk',
        override: true));
    return ret.realUri.toString();
  }
}
