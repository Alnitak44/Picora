library;

import 'dart:convert';
import 'dart:io';

import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluro/fluro.dart';

import 'package:picora/picture_host_manage/manage_api/alist_manage_api.dart';
import 'package:picora/picture_host_manage/manage_api/aliyun_manage_api.dart';
import 'package:picora/picture_host_manage/manage_api/aws_manage_api.dart';
import 'package:picora/picture_host_manage/manage_api/github_manage_api.dart';
import 'package:picora/picture_host_manage/manage_api/imgur_manage_api.dart';
import 'package:picora/picture_host_manage/manage_api/lskypro_manage_api.dart';
import 'package:picora/picture_host_manage/manage_api/qiniu_manage_api.dart';
import 'package:picora/picture_host_manage/manage_api/smms_manage_api.dart';
import 'package:picora/picture_host_manage/manage_api/tencent_manage_api.dart';
import 'package:picora/picture_host_manage/manage_api/upyun_manage_api.dart';
import 'package:picora/widgets/common_widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'package:picora/utils/global.dart';
import 'package:picora/utils/common_functions.dart';

import 'package:picora/picture_host_configure/configure_page/configure_export.dart';

import 'package:picora/widgets/net_loading_dialog.dart';

import 'package:picora/router/application.dart';
import 'package:picora/router/routers.dart';

part 'picture_host_import_qr.dart';

//a configure page for user to show configure entry
class AllPShost extends StatefulWidget {
  const AllPShost({super.key});

  @override
  AllPShostState createState() => AllPShostState();
}

class AllPShostState extends State<AllPShost> {
  Future<void> _scan() async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const QRScannerPage()),
      );

      if (result != null) {
        setState(() => Global.qrScanResult = result);
      }
    } catch (e) {
      _logError('_scan', {}, e);
      setState(() {
        Global.qrScanResult = e.toString();
      });
    }
  }

  static Future<String> get localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<void> exportConfiguration([String? pshost]) async {
    try {
      String configPath = await localPath;
      String defaultUser = Global.getUser();
      Map<String, String> configFilePaths = {
        "smms": "$configPath/${defaultUser}_smms_config.txt",
        "lankong": "$configPath/${defaultUser}_host_config.txt",
        "github": "$configPath/${defaultUser}_github_config.txt",
        "imgur": "$configPath/${defaultUser}_imgur_config.txt",
        "qiniu": "$configPath/${defaultUser}_qiniu_config.txt",
        "tcyun": "$configPath/${defaultUser}_tencent_config.txt",
        "aliyun": "$configPath/${defaultUser}_aliyun_config.txt",
        "upyun": "$configPath/${defaultUser}_upyun_config.txt",
        "ftp": "$configPath/${defaultUser}_ftp_config.txt",
        "aws": "$configPath/${defaultUser}_aws_config.txt",
        "alist": "$configPath/${defaultUser}_alist_config.txt",
        "webdav": "$configPath/${defaultUser}_webdav_config.txt",
      };

      Map<String, dynamic> configMap = {};

      if (pshost != null) {
        if (!configFilePaths.containsKey(pshost)) return;

        String filePath = configFilePaths[pshost]!;
        if (!File(filePath).existsSync()) {
          return showToast("配置文件不存在");
        }

        String config = await File(filePath).readAsString();
        if (config.isEmpty) {
          return showToast("该图床未配置");
        }

        configMap[pshost] = jsonDecode(config);
      } else {
        for (var key in configFilePaths.keys) {
          String filePath = configFilePaths[key]!;
          if (!File(filePath).existsSync()) continue;

          String config = await File(filePath).readAsString();
          if (config.isEmpty) continue;

          configMap[key] = jsonDecode(config);
        }
      }

      if (configMap.isEmpty) {
        return showToast("没有可导出的配置");
      }

      String configJson = jsonEncode(configMap).replaceAll('None', '');
      await Clipboard.setData(ClipboardData(text: configJson));
      showToast(pshost != null ? "$pshost配置已复制到剪贴板" : "配置已复制到剪贴板");
    } catch (e) {
      _logError(
        pshost != null ? 'exportConfiguration' : 'exportAllConfiguration',
        pshost != null ? {"pshost": pshost} : {},
        e,
      );
      showToast("导出失败");
    }
  }

  Future<dynamic> processingQRCodeResult() async {
    try {
      String result = Global.qrScanResult;
      Global.qrScanResult = "";
      Map<String, dynamic> jsonResult = jsonDecode(result);

      // Check if any supported services exist in the JSON
      List<String> supportedServices = [
        'smms',
        'openlist',
        'openlistplist',
        'alist',
        'alistplist',
        'aws-s3-plist',
        'aws-s3',
        'github',
        'lankong',
        'lskyplist',
        'imgur',
        'qiniu',
        'tcyun',
        'aliyun',
        'upyun',
      ];

      if (!supportedServices.any(
        (service) => jsonResult.containsKey(service),
      )) {
        return showToast("不包含支持的图床配置信息");
      }

      // Handle each service configuration
      if (jsonResult['smms'] != null) _configureSmms(jsonResult);
      if (jsonResult['aws-s3-plist'] != null || jsonResult['aws-s3'] != null) {
        _configureAws(jsonResult);
      }
      if (jsonResult['openlist'] != null ||
          jsonResult['openlistplist'] != null ||
          jsonResult['alist'] != null ||
          jsonResult['alistplist'] != null) {
        _configureAlist(jsonResult);
      }
      if (jsonResult['github'] != null) _configureGithub(jsonResult);
      if (jsonResult['lankong'] != null || jsonResult['lskyplist'] != null) {
        _configureLankong(jsonResult);
      }
      if (jsonResult['imgur'] != null) _configureImgur(jsonResult);
      if (jsonResult['qiniu'] != null) _configureQiniu(jsonResult);
      if (jsonResult['tcyun'] != null) _configureTencent(jsonResult);
      if (jsonResult['aliyun'] != null) _configureAliyun(jsonResult);
      if (jsonResult['upyun'] != null) _configureUpyun(jsonResult);

      return true;
    } catch (e) {
      _logError('processingQRCodeResult', {}, e);
      showToast("导入失败");
    }
  }

  // UI Building Methods
  Widget _buildSettingCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    Widget? trailing,
    Color? iconColor,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 2.0,
      ),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color:
              iconColor ??
              Theme.of(context).primaryColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor ?? Theme.of(context).primaryColor),
      ),
      title: Text(title),
      onTap: onTap,
      trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 16),
    );
  }

  List<SimpleDialogOption> _buildSimpleDialogOptions(BuildContext context) {
    // Define service mappings once
    final serviceMap = {
      "全部导出": null,
      "OpenList": 'alist',
      '阿里云': 'aliyun',
      'FTP-SSH/SFTP': 'ftp',
      'Github': 'github',
      'Imgur': 'imgur',
      '兰空图床': 'lankong',
      '七牛云': 'qiniu',
      'S3兼容平台': 'aws',
      'SM.MS': 'smms',
      '腾讯云': 'tcyun',
      '又拍云': 'upyun',
      'WebDAV': 'webdav',
    };

    return serviceMap.entries.map((entry) {
      return SimpleDialogOption(
        child: Text(entry.key, textAlign: TextAlign.center),
        onPressed: () {
          entry.value == null
              ? exportConfiguration()
              : exportConfiguration(entry.value!);
          Navigator.pop(context);
        },
      );
    }).toList();
  }

  // Service navigation helper
  void _navigateToService(String route) {
    Application.router.navigateTo(
      context,
      route,
      transition: TransitionType.cupertino,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Define service items
    final serviceItems = [
      {
        'title': '默认图床选择',
        'icon': Icons.photo_library,
        'route': Routes.defaultPShostSelect,
      },
      {
        'title': 'OpenList',
        'icon': Icons.folder_shared,
        'route': Routes.alistPShostSelect,
      },
      {
        'title': '阿里云OSS',
        'icon': Icons.cloud_upload,
        'route': Routes.aliyunPShostSelect,
      },
      {
        'title': 'FTP-SSH/SFTP',
        'icon': Icons.storage,
        'route': Routes.ftpPShostSelect,
      },
      {
        'title': 'Github图床',
        'icon': Icons.code,
        'route': Routes.githubPShostSelect,
      },
      {
        'title': 'Imgur图床',
        'icon': Icons.image,
        'route': Routes.imgurPShostSelect,
      },
      {
        'title': '兰空图床V2',
        'icon': Icons.cloud,
        'route': Routes.lskyproPShostSelect,
      },
      {
        'title': '七牛云存储',
        'icon': Icons.cloud_circle,
        'route': Routes.qiniuPShostSelect,
      },
      {
        'title': 'S3兼容平台',
        'icon': Icons.storage_rounded,
        'route': Routes.awsPShostSelect,
      },
      {
        'title': 'SM.MS图床',
        'icon': Icons.camera,
        'route': Routes.smmsPShostSelect,
      },
      {
        'title': '腾讯云COS V5',
        'icon': Icons.cloud_queue,
        'route': Routes.tencentPShostSelect,
      },
      {
        'title': '又拍云存储',
        'icon': Icons.cloud_done,
        'route': Routes.upyunPShostSelect,
      },
      {
        'title': 'WebDAV',
        'icon': Icons.web,
        'route': Routes.webdavPShostSelect,
      },
    ];

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        leading: getLeadingIcon(context),
        title: titleText('图床设置'),
        flexibleSpace: getFlexibleSpace(context),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: 8),
          _buildSettingCard(
            title: '导入导出',
            children: [
              _buildSettingItem(
                title: '二维码扫描导入PicGo配置',
                icon: Icons.qr_code_scanner,
                onTap: () async {
                  await _scan();
                  if (context.mounted) {
                    showDialog(
                      context: this.context,
                      barrierDismissible: false,
                      builder: (context) => NetLoadingDialog(
                        outsideDismiss: false,
                        loading: true,
                        loadingText: "配置中...",
                        requestCallBack: processingQRCodeResult(),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          _buildSettingCard(
            title: '图床配置',
            children: [
              for (int i = 0; i < serviceItems.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                _buildSettingItem(
                  title: serviceItems[i]['title'] as String,
                  icon: serviceItems[i]['icon'] as IconData,
                  onTap: () =>
                      _navigateToService(serviceItems[i]['route'] as String),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
      floatingActionButton: SizedBox(
        height: 50,
        width: 50,
        child: FloatingActionButton(
          heroTag: 'copyConfig',
          elevation: 3,
          backgroundColor: Theme.of(context).primaryColor,
          onPressed: () async {
            await showDialog(
              barrierDismissible: true,
              context: context,
              builder: (context) => SimpleDialog(
                title: const Text(
                  '选择要复制配置的图床',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                children: _buildSimpleDialogOptions(context),
              ),
            );
          },
          child: const Icon(
            Icons.outbox_outlined,
            color: Colors.white,
            size: 30,
          ),
        ),
      ),
    );
  }
}

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  QRScannerPageState createState() => QRScannerPageState();
}

class QRScannerPageState extends State<QRScannerPage> {
  MobileScannerController cameraController = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    autoStart: true,
  );
  bool _hasDetected = false;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasDetected) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      _hasDetected = true;
      Navigator.pop(context, barcodes.first.rawValue!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('二维码扫描'),
        centerTitle: true,
        actions: [
          ValueListenableBuilder(
            valueListenable: cameraController,
            builder: (context, state, child) {
              return IconButton(
                icon: Icon(
                  cameraController.torchEnabled
                      ? Icons.flash_on
                      : Icons.flash_off,
                ),
                iconSize: 32.0,
                onPressed: () => cameraController.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: cameraController, onDetect: _onDetect),
          // Overlay with scanning area
          Container(
            decoration: ShapeDecoration(
              shape: QrScannerOverlayShape(
                borderColor: Theme.of(context).primaryColor,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 8,
                cutOutSize: 250,
              ),
            ),
          ),
          // Instructions
          const Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Text(
              '请将二维码放入扫描框内',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class QrScannerOverlayShape extends ShapeBorder {
  const QrScannerOverlayShape({
    this.borderColor = Colors.red,
    this.borderWidth = 3.0,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 80),
    this.borderRadius = 0,
    this.borderLength = 40,
    double? cutOutSize,
    double? cutOutHeight,
    double? cutOutWidth,
  }) : cutOutWidth = cutOutWidth ?? cutOutSize ?? 250,
       cutOutHeight = cutOutHeight ?? cutOutSize ?? 250;

  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutWidth;
  final double cutOutHeight;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path getLeftTopPath(Rect rect) {
      return Path()
        ..moveTo(rect.left, rect.bottom)
        ..lineTo(rect.left, rect.top + borderRadius)
        ..quadraticBezierTo(
          rect.left,
          rect.top,
          rect.left + borderRadius,
          rect.top,
        )
        ..lineTo(rect.right, rect.top);
    }

    return getLeftTopPath(rect)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.top);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final width = rect.width;
    final borderWidthSize = width / 2;
    final height = rect.height;
    final borderHeightSize = height / 2;
    final cutOutWidth = this.cutOutWidth < width
        ? this.cutOutWidth
        : width - borderWidth;
    final cutOutHeight = this.cutOutHeight < height
        ? this.cutOutHeight
        : height - borderWidth;

    final backgroundPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final boxPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final cutOutRect = Rect.fromLTWH(
      borderWidthSize - cutOutWidth / 2,
      borderHeightSize - cutOutHeight / 2,
      cutOutWidth,
      cutOutHeight,
    );

    canvas
      ..saveLayer(rect, backgroundPaint)
      ..drawRect(rect, backgroundPaint)
      ..drawRRect(
        RRect.fromRectAndCorners(
          cutOutRect,
          topLeft: Radius.circular(borderRadius),
          topRight: Radius.circular(borderRadius),
          bottomLeft: Radius.circular(borderRadius),
          bottomRight: Radius.circular(borderRadius),
        ),
        backgroundPaint..blendMode = BlendMode.clear,
      )
      ..restore();

    final borderPath = Path();

    borderPath
      ..moveTo(cutOutRect.left - borderWidth / 2, cutOutRect.top + borderLength)
      ..lineTo(cutOutRect.left - borderWidth / 2, cutOutRect.top)
      ..lineTo(cutOutRect.left + borderLength, cutOutRect.top);

    borderPath
      ..moveTo(cutOutRect.right - borderLength, cutOutRect.top)
      ..lineTo(cutOutRect.right + borderWidth / 2, cutOutRect.top)
      ..lineTo(
        cutOutRect.right + borderWidth / 2,
        cutOutRect.top + borderLength,
      );

    borderPath
      ..moveTo(
        cutOutRect.right + borderWidth / 2,
        cutOutRect.bottom - borderLength,
      )
      ..lineTo(cutOutRect.right + borderWidth / 2, cutOutRect.bottom)
      ..lineTo(cutOutRect.right - borderLength, cutOutRect.bottom);

    borderPath
      ..moveTo(cutOutRect.left + borderLength, cutOutRect.bottom)
      ..lineTo(cutOutRect.left - borderWidth / 2, cutOutRect.bottom)
      ..lineTo(
        cutOutRect.left - borderWidth / 2,
        cutOutRect.bottom - borderLength,
      );

    canvas.drawPath(borderPath, boxPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return QrScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth,
      overlayColor: overlayColor,
    );
  }
}
