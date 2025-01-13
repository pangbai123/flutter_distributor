class PublishAppStoreConfig {
  final String? version; // 版本号
  final String? whatsNew; // 更新日志

  // 构造函数
  PublishAppStoreConfig({
    this.version,
    this.whatsNew,
  });

  /// 从 environment 和 publishArguments 中解析配置
  static PublishAppStoreConfig parse(
    Map<String, String>? environment,
  ) {
    // 从发布参数获取版本号和更新日志
    String? version =
        environment?['APP_VERSION'] ?? '1.0.0'; // 如果没有提供，使用默认值 1.0.0

    String? whatsNew =
        environment?['WHAT_IS_NEW'] ?? 'No new updates'; // 如果没有提供，使用默认更新日志

    return PublishAppStoreConfig(version: version, whatsNew: whatsNew);
  }

  /// 将配置转为命令行参数（例如上传到 App Store Connect）
  List<String> toAppStoreCliDistributeArgs() {
    return [
      '--version', version ?? '1.0.0', // 默认版本号
      '--whats-new', whatsNew ?? 'No new updates', // 默认更新日志
    ];
  }
}
