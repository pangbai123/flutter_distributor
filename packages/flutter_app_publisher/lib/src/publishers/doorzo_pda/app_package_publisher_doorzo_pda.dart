import 'dart:io';

import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/api/http_client.dart';
import 'package:flutter_app_publisher/src/publishers/doorzo/app_package_publisher_doorzo.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_oss_aliyun/flutter_oss_aliyun.dart';

const kEnvDoorzoAccount = 'DOORZO_ACCOUNT';
const kEnvDoorzoPwd = 'DOORZO_PWD';

class AppPackagePublisherDoorzoPda extends AppPackagePublisher {
  @override
  String get name => 'doorzoPda';

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
      DoorzoHttpClient.instance.init();
      var url = await uploadApp(file, onPublishProgress);
      print('上传文件成功：${url}');
      await submit(url);
      return PublishResult(url: globalEnvironment[kEnvAppName]! + name + '提交成功}');
    }  catch (e) {
      print("app提交失败========$name$e=========");
      exit(1);
    }
  }

  Future submit(String url) async {
    await DoorzoHttpClient.instance.syncRequest(
      {
        'n': 'Sig.Admin.Warehouse.Login',
        'user': globalEnvironment[kEnvDoorzoAccount],
        'password': globalEnvironment[kEnvDoorzoPwd],
      },
      isGet: false,
    );
    print('登录成功');

    await DoorzoHttpClient.instance.syncRequest(
      {
        'n': 'Sig.Admin.Warehouse.UpgradeWarehouseAppInfo',
        'Version': globalEnvironment[kEnvVersionName],
        'Content': globalEnvironment[kEnvUpdateLog],
        'ForceUpgrade': globalEnvironment[kEnvForceUpgrade] == '是' ? 1 : 0,
        'Url': url,
      },
      isGet: false,
    );
    print('发布成功');
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
    return ret.realUri.toString();
  }
}
