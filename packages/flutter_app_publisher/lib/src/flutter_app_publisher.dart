import 'dart:io';

import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/doorzo/app_package_publisher_doorzo.dart';
import 'package:flutter_app_publisher/src/publishers/honor/app_package_publisher_honor.dart';
import 'package:flutter_app_publisher/src/publishers/huawei/app_package_publisher_huawei.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_app_publisher/src/publishers/publishers.dart';
import 'package:flutter_app_publisher/src/publishers/vivo/app_package_publisher_vivo.dart';

class FlutterAppPublisher {
  final List<AppPackagePublisher> _publishers = [
    AppPackagePublisherAppCenter(),
    AppPackagePublisherAppStore(),
    AppPackagePublisherFir(),
    AppPackagePublisherFirebase(),
    AppPackagePublisherFirebaseHosting(),
    AppPackagePublisherGithub(),
    AppPackagePublisherPgyer(),
    AppPackagePublisherPlayStore(),
    AppPackagePublisherQiniu(),
    AppPackagePublisherVercel(),
    AppPackagePublisherOppo(),
    AppPackagePublisherVivo(),
    AppPackagePublisherMi(),
    AppPackagePublisherHuawei(),
    AppPackagePublisherHonor(),
    AppPackagePublisherDoorzo(),
  ];

  Future<PublishResult> publish(
    FileSystemEntity fileSystemEntity, {
    required String target,
    Map<String, String>? environment,
    Map<String, dynamic>? publishArguments,
    PublishProgressCallback? onPublishProgress,
  }) async {
    AppPackagePublisher publisher = _publishers.firstWhere(
      (e) => e.name == target,
    );
    return await publisher.publish(
      fileSystemEntity,
      environment: environment,
      publishArguments: publishArguments,
      onPublishProgress: onPublishProgress,
    );
  }
}
