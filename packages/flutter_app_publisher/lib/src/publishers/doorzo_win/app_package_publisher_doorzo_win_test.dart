import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_oss_aliyun/flutter_oss_aliyun.dart';

const kEnvDoorzoOssInfoTest = 'DOORZO_OSS_INFO_TEST';

/// 测试包只上传阿里云，不登录、不提交升级接口。
class AppPackagePublisherDoorzoWinTest extends AppPackagePublisher {
  @override
  String get name => 'doorzoWinTest';

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
      var url = await uploadApp(file, onPublishProgress);
      if (url == '') {
        throw Exception("上传失败");
      }
      print('上传文件成功：${url}');
      return PublishResult(
          url: globalEnvironment[kEnvAppName]! + name + '上传成功');
    } catch (e) {
      print("app提交失败========$name$e=========");
      exit(1);
    }
  }

  ///上传文件到阿里云测试目录
  Future<String> uploadApp(
    File file,
    PublishProgressCallback? onPublishProgress,
  ) async {
    var info = globalEnvironment[kEnvDoorzoOssInfoTest]!.split('_');
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

    var key = info[2] + '/win.exe';
    try {
      var ret = await Client().putObjectFile(
        file.path,
        fileKey: key,
        option: PutRequestOption(
          onSendProgress: (count, total) {
            onPublishProgress?.call(count, total);
          },
          override: true,
          aclModel: AclMode.publicRead,
          storageType: StorageType.ia,
          headers: {"cache-control": "no-cache"},
        ),
      );
      return ret.realUri.toString();
    } catch (e) {
      if (e is DioException) {
        print(e.response);
      } else {
        print(e);
      }
    }
    return '';
  }
}
