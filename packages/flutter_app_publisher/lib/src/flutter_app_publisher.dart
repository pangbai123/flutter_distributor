import 'dart:io';

import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/doorzo/app_package_publisher_doorzo.dart';
import 'package:flutter_app_publisher/src/publishers/doorzo_pda/app_package_publisher_doorzo_pda.dart';
import 'package:flutter_app_publisher/src/publishers/doorzo_win/app_package_publisher_doorzo_win.dart';
import 'package:flutter_app_publisher/src/publishers/hmos/app_package_publisher_hmos.dart';
import 'package:flutter_app_publisher/src/publishers/honor/app_package_publisher_honor.dart';
import 'package:flutter_app_publisher/src/publishers/huawei/app_package_publisher_huawei.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_app_publisher/src/publishers/playstore/app_package_publisher_playstore.dart';
import 'package:flutter_app_publisher/src/publishers/publishers.dart';
import 'package:flutter_app_publisher/src/publishers/samsung/app_package_publisher_samsung.dart';
import 'package:flutter_app_publisher/src/publishers/tencent/app_package_publisher_tencent.dart';
import 'package:flutter_app_publisher/src/publishers/vivo/app_package_publisher_vivo.dart';
import 'package:flutter_app_publisher/src/publishers/vivo_oversea/app_package_publisher_vivo_oversea.dart';

class FlutterAppPublisher {
  final List<AppPackagePublisher> _publishers = [
    AppPackagePublisherAppStore(),
    AppPackagePublisherPgyer(),
    AppPackagePublisherPlayStore(),
    AppPackagePublisherOppo(),
    AppPackagePublisherVivo(),
    AppPackagePublisherMi(),
    AppPackagePublisherHuawei(),
    AppPackagePublisherHonor(),
    AppPackagePublisherDoorzo(),
    AppPackagePublisherSamsung(),
    AppPackagePublisherVivoOversea(),
    AppPackagePublisherDoorzoPda(),
    AppPackagePublisherDoorzoWin(),
    AppPackagePublisherHmos(),
    AppPackagePublisherTencent()
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
