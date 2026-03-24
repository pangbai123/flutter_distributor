import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/api/http_client.dart';
import 'package:flutter_app_publisher/src/publishers/doorzo_pda/app_package_publisher_doorzo_pda.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_oss_aliyun/flutter_oss_aliyun.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

const kEnvDoorzoOssInfo = 'DOORZO_OSS_INFO';
const kEnvDoorzoUrlKey = 'DOORZO_URL_KEY';
const kEnvDoorzoVersionKey = 'DOORZO_VERSION_KEY';

const kEnvDoorzoLightKey = 'DOORZO_LIGHT_VERSION_KEY';
const kEnvDoorzoNewKey = 'DOORZO_NEW_VERSION_KEY';


const kEnvDoNotUploadApp = 'DOORZO_DO_NOT_UPLOAD_APP';
const kEnvReviewVersionKey = 'DOORZO_IOS_REVIEW_VERSION_KEY';
const kEnvReviewVersionName = 'DOORZO_IOS_REVIEW_VERSION_NAME';


class AppPackagePublisherDoorzo extends AppPackagePublisher {
  @override
  String get name => 'doorzo';

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

      var doNotUploadApp = globalEnvironment[kEnvDoNotUploadApp];
      print("doNotUploadApp=======$doNotUploadApp======");
      if (doNotUploadApp == "true") {
        await submitAppInfo(versionKey: globalEnvironment[kEnvReviewVersionKey], versionName: globalEnvironment[kEnvReviewVersionName]);
        return PublishResult(url: '修改App审核版本信息提交成功');
      }
      File file = fileSystemEntity as File;
      var url = await uploadApp(file, onPublishProgress);
      print('上传文件成功：${url}');
      await submit(url);
    }  catch (e) {
      print("app提交失败========$name$e=========");
      exit(1);
    }
    return PublishResult(url: globalEnvironment[kEnvAppName]! + name + '提交成功}');
  }

  submitAppInfo({String? versionKey, String? versionName}) async {

    print('开始登录==========');
    //修改我们后台版本信息
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
        'n': 'Sig.Admin.Warehouse.UpgradeFrontAppInfo',
        if ((versionKey?.length ?? 0) > 0)"${versionKey}": versionName??"",
      },
      isGet: false,
    );
    print('修改版本号${globalEnvironment[kEnvReviewVersionKey]}========${versionName}成功');
  }

  Future submit(String url) async {
    //修改我们后台版本信息
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
        'n': 'Sig.Admin.Warehouse.UpgradeFrontAppInfo',
        if (globalEnvironment[kEnvDoorzoVersionKey] != null)
          "${globalEnvironment[kEnvDoorzoVersionKey]}":
              globalEnvironment[kEnvVersionName],
        if (globalEnvironment[kEnvDoorzoUrlKey] != null)globalEnvironment[kEnvDoorzoUrlKey]!: url,
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
    print("=========$info========");
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
        globalEnvironment[kEnvAliAppName]! +
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
        targetFileKey: 'publish/' + globalEnvironment[kEnvAliAppName]! + '.apk',
        override: true));
    return ret.realUri.toString();
  }
}
