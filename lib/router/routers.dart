import 'package:picora/hero/compatibility_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:fluro/fluro.dart';

import 'package:picora/router/router_handler.dart';

class Routes {
  static String webviewPage = '/webview';
  static String root = "/";
  static String homePage = "/homePage";
  static String albumUploadedImages = "/albumUploadedImages";
  static String albumImagePreview = "/albumImagePreview";
  static String webdavImagePreview = "/webdavImagePreview";
  static String localImagePreview = "/localImagePreview";
  static String configurePage = "/configurePage";
  static String configurePageLogger = "/configurePageLogger";
  static String compressConfigurePage = "/compressConfigurePage";
  static String appPassword = "/appPassword";
  static String allPShost = "/allPShost";
  static String defaultPShostSelect = "/defaultPShostSelect";
  static String lskyproPShostSelect = "/lskyproPShostSelect";
  static String smmsPShostSelect = "/smmsPShostSelect";
  static String githubPShostSelect = "/githubPShostSelect";
  static String imgurPShostSelect = "/imgurPShostSelect";
  static String aliyunPShostSelect = "/aliyunPShostSelect";
  static String tencentPShostSelect = "/tencentPShostSelect";
  static String qiniuPShostSelect = "/qiniuPShostSelect";
  static String upyunPShostSelect = "/upyunPShostSelect";
  static String ftpPShostSelect = "/ftpPShostSelect";
  static String awsPShostSelect = "/awsPShostSelect";
  static String alistPShostSelect = "/alistPShostSelect";
  static String webdavPShostSelect = "/webdavPShostSelect";
  static String configureStorePage = "/configureStorePage";
  static String alistConfigureStoreEditPage = "/alistConfigureStoreEditPage";
  static String aliyunConfigureStoreEditPage = "/aliyunConfigureStoreEditPage";
  static String awsConfigureStoreEditPage = "/awsConfigureStoreEditPage";
  static String ftpConfigureStoreEditPage = "/ftpConfigureStoreEditPage";
  static String githubConfigureStoreEditPage = "/githubConfigureStoreEditPage";
  static String imgurConfigureStoreEditPage = "/imgurConfigureStoreEditPage";
  static String lskyproConfigureStoreEditPage = "/lskyConfigureStoreEditPage";
  static String qiniuConfigureStoreEditPage = "/qiniuConfigureStoreEditPage";
  static String smmsConfigureStoreEditPage = "/smmsConfigureStoreEditPage";
  static String tencentConfigureStoreEditPage =
      "/tencentConfigureStoreEditPage";
  static String upyunConfigureStoreEditPage = "/upyunConfigureStoreEditPage";
  static String webdavConfigureStoreEditPage = "/webdavConfigureStoreEditPage";
  static String commonConfig = "/commonConfig";
  static String renameFile = "/renameFile";
  static String linkFormatSelect = "/linkFormatSelect";
  static String changeTheme = "/changeTheme";
  static String emptyDatabase = "/emptyDatabase";
  static String updateLog = "/updateLog";
  static String tencentBucketInformation = "/tencentBucketInformation";
  static String tencentNewBucketConfig = "/tencentNewBucketConfig";
  static String tencentFileExplorer = "/tencentFileExplorer";
  static String tencentFileInformation = "/tencentFileInformation";
  static String tencentBucketList = "/tencentBucketList";
  static String fileExplorer = "/fileExplorer";
  static String smmsManageHomePage = "/smmsManageHomePage";
  static String smmsFileExplorer = "/smmsFileExplorer";
  static String smmsFileInformation = "/smmsFileInformation";
  static String userInformationPage = '/userInformationPage';
  static String pictureHostInfoPage = '/pictureHostInfoPage';
  static String aliyunBucketList = '/aliyunBucketList';
  static String aliyunNewBucketConfig = "/aliyunNewBucketConfig";
  static String aliyunBucketInformation = "/aliyunBucketInformation";
  static String aliyunFileExplorer = "/aliyunFileExplorer";
  static String aliyunFileInformation = "/aliyunFileInformation";
  static String upyunLogIn = '/upyunLogIn';
  static String upyunFileExplorer = "/upyunFileExplorer";
  static String upyunBucketList = "/upyunBucketList";
  static String upyunBucketInformation = "/upyunBucketInformation";
  static String upyunTokenManagePage = "/upyunTokenManagePage";
  static String upyunNewBucketConfig = "/upyunNewBucketConfig";
  static String upyunFileInformationPage = "/upyunFileInformationPage";
  static String qiniuBucketList = "/qiniuBucketList";
  static String qiniuNewBucketConfig = "/qiniuNewBucketConfig";
  static String qiniuBucketDomainAreaConfig = "/qiniuBucketDomainAreaConfig";
  static String qiniuFileExplorer = "/qiniuFileExplorer";
  static String qiniuFileInformation = "/qiniuFileInformation";
  static String lskyproManageHomePage = "/lskyproManageHomePage";
  static String lskyproFileExplorer = "/lskyproFileExplorer";
  static String lskyproFileInformation = "/lskyproFileInformation";
  static String githubManageHomePage = "/githubManageHomePage";
  static String githubReposList = "/githubReposList";
  static String githubRepoInformation = "/githubRepoInformation";
  static String githubNewRepoConfig = "/githubNewRepoConfig";
  static String githubFileExplorer = "/githubFileExplorer";
  static String githubFileInformation = "/githubFileInformation";
  static String imgurLogIn = "/imgurLogIn";
  static String imgurFileExplorer = "/imgurFileExplorer";
  static String imgurTokenManagePage = "/imgurTokenManagePage";
  static String imgurFileInformation = "/imgurFileInformation";
  static String sftpFileExplorer = "/sftpFileExplorer";
  static String sftpFileInformation = "/sftpFileInformation";
  static String sftpLocalImagePreview = "/sftpLocalImagePreview";
  static String mdPreview = "/mdPreview";
  static String awsBucketList = "/awsBucketList";
  static String awsNewBucketConfig = "/awsNewBucketConfig";
  static String awsFileExplorer = "/awsFileExplorer";
  static String awsFileInformation = "/awsFileInformation";
  static String alistBucketList = "/alistBucketList";
  static String alistBucketInformation = "/alistBucketInformation";
  static String alistFileExplorer = "/alistFileExplorer";
  static String alistFileInformation = "/alistFileInformation";
  static String pdfViewer = "/pdfViewer";
  static String webdavFileExplorer = "/webdavFileExplorer";
  static String webdavFileInformation = "/webdavFileInformation";
  static String baseUpDownloadManagePage = "/baseUpDownloadManagePage";

  static void configureRoutes(FluroRouter router) {
    router.notFoundHandler = Handler(
        handlerFunc: (BuildContext? context, Map<String, List<String>> params) {
      if (kDebugMode) {
        print("ROUTE WAS NOT FOUND !!!");
      }
      return null;
    });
    router.define(webviewPage, handler: webviewHandler);
    router.define(root, handler: rootHandler);
    router.define(homePage, handler: modernPageHandler(0));
    router.define(albumUploadedImages, handler: modernPageHandler(1));
    router.define(albumImagePreview, handler: albumImagePreviewHandler);
    router.define(webdavImagePreview, handler: webdavImagePreviewHandler);
    router.define(localImagePreview, handler: localImagePreviewHandler);
    router.define(configurePage, handler: modernPageHandler(3));
    router.define(compressConfigurePage, handler: modernPageHandler(3));
    router.define(allPShost, handler: modernPageHandler(2));
    router.define(defaultPShostSelect, handler: modernPageHandler(2));
    router.define(lskyproPShostSelect,
        handler: modernRepositoryHandler('lsky.pro'));
    router.define(smmsPShostSelect, handler: modernRepositoryHandler('sm.ms'));
    router.define(githubPShostSelect,
        handler: modernRepositoryHandler('github'));
    router.define(imgurPShostSelect, handler: modernRepositoryHandler('imgur'));
    router.define(aliyunPShostSelect,
        handler: modernRepositoryHandler('aliyun'));
    router.define(tencentPShostSelect,
        handler: modernRepositoryHandler('tencent'));
    router.define(qiniuPShostSelect, handler: modernRepositoryHandler('qiniu'));
    router.define(upyunPShostSelect, handler: modernRepositoryHandler('upyun'));
    router.define(ftpPShostSelect, handler: modernRepositoryHandler('ftp'));
    router.define(awsPShostSelect, handler: modernRepositoryHandler('aws'));
    router.define(alistPShostSelect, handler: modernRepositoryHandler('alist'));
    router.define(webdavPShostSelect,
        handler: modernRepositoryHandler('webdav'));
    router.define(alistConfigureStoreEditPage,
        handler: modernSlotHandler('alist'));
    router.define(aliyunConfigureStoreEditPage,
        handler: modernSlotHandler('aliyun'));
    router.define(awsConfigureStoreEditPage, handler: modernSlotHandler('aws'));
    router.define(ftpConfigureStoreEditPage, handler: modernSlotHandler('ftp'));
    router.define(githubConfigureStoreEditPage,
        handler: modernSlotHandler('github'));
    router.define(imgurConfigureStoreEditPage,
        handler: modernSlotHandler('imgur'));
    router.define(lskyproConfigureStoreEditPage,
        handler: modernSlotHandler('lsky.pro'));
    router.define(qiniuConfigureStoreEditPage,
        handler: modernSlotHandler('qiniu'));
    router.define(smmsConfigureStoreEditPage,
        handler: modernSlotHandler('sm.ms'));
    router.define(tencentConfigureStoreEditPage,
        handler: modernSlotHandler('tencent'));
    router.define(upyunConfigureStoreEditPage,
        handler: modernSlotHandler('upyun'));
    router.define(webdavConfigureStoreEditPage,
        handler: modernSlotHandler('webdav'));
    router.define(commonConfig, handler: modernPageHandler(3));
    router.define(renameFile, handler: modernPageHandler(3));
    router.define(linkFormatSelect, handler: modernPageHandler(3));
    router.define(changeTheme, handler: modernPageHandler(3));
    router.define(emptyDatabase, handler: modernPageHandler(3));
    router.define(updateLog, handler: updateLogHandler);
    router.define(tencentBucketInformation,
        handler: tencentBucketInformationHandler);
    router.define(tencentNewBucketConfig, handler: newTencentBucketHandler);
    router.define(tencentFileExplorer, handler: tencentFileExplorerHandler);
    router.define(tencentFileInformation,
        handler: tencentFileInformationHandler);
    router.define(tencentBucketList, handler: tencentBucketListHandler);
    router.define(fileExplorer, handler: fileExplorerHandler);
    router.define(smmsManageHomePage, handler: smmsManageHomePageHandler);
    router.define(smmsFileExplorer, handler: smmsFileExplorerHandler);
    router.define(smmsFileInformation, handler: smmsFileInformationHandler);
    router.define(aliyunBucketList, handler: aliyunBucketListHandler);
    router.define(aliyunNewBucketConfig, handler: newAliyunBucketHandler);
    router.define(aliyunBucketInformation,
        handler: aliyunBucketInformationHandler);
    router.define(aliyunFileExplorer, handler: aliyunFileExplorerHandler);
    router.define(aliyunFileInformation, handler: aliyunFileInformationHandler);
    router.define(configurePageLogger, handler: modernPageHandler(3));
    router.define(upyunFileExplorer, handler: upyunFileExplorerHandler);
    router.define(upyunLogIn, handler: upyunLogInHandler);
    router.define(upyunBucketList, handler: upyunBucketListHandler);
    router.define(upyunBucketInformation,
        handler: upyunBucketInformationHandler);
    router.define(upyunTokenManagePage, handler: upyunTokenManageHandler);
    router.define(upyunNewBucketConfig, handler: newUpyunBucketHandler);
    router.define(upyunFileInformationPage,
        handler: upyunFileInformationHandler);
    router.define(qiniuBucketList, handler: qiniuBucketListHandler);
    router.define(qiniuNewBucketConfig, handler: newQiniuBucketHandler);
    router.define(qiniuBucketDomainAreaConfig,
        handler: qiniuBucketDomainAreaConfigHandler);
    router.define(qiniuFileExplorer, handler: qiniuFileExplorerHandler);
    router.define(qiniuFileInformation, handler: qiniuFileInformationHandler);
    router.define(lskyproManageHomePage, handler: lskyproManageHomePageHandler);
    router.define(lskyproFileExplorer, handler: lskyproFileExplorerHandler);
    router.define(lskyproFileInformation,
        handler: lskyproFileInformationHandler);
    router.define(githubManageHomePage, handler: githubManageHomePageHandler);
    router.define(githubReposList, handler: githubReposListHandler);
    router.define(githubRepoInformation, handler: githubRepoInformationHandler);
    router.define(githubNewRepoConfig, handler: githubNewRepoConfigHandler);
    router.define(githubFileExplorer, handler: githubFileExplorerHandler);
    router.define(githubFileInformation, handler: githubFileInformationHandler);
    router.define(imgurLogIn, handler: imgurLogInHandler);
    router.define(imgurFileExplorer, handler: imgurFileExplorerHandler);
    router.define(imgurTokenManagePage, handler: imgurTokenManageHandler);
    router.define(imgurFileInformation, handler: imgurFileInformationHandler);
    router.define(sftpFileExplorer, handler: sftpFileExplorerHandler);
    router.define(sftpFileInformation, handler: sftpFileInformationHandler);
    router.define(sftpLocalImagePreview, handler: sftplocalImagePreviewHandler);
    router.define(mdPreview, handler: mdFilePreviewHandler);
    router.define(awsBucketList, handler: awsBucketListHandler);
    router.define(awsNewBucketConfig, handler: newAwsBucketHandler);
    router.define(awsFileExplorer, handler: awsFileExplorerHandler);
    router.define(awsFileInformation, handler: awsFileInformationHandler);
    router.define(configureStorePage, handler: modernPageHandler(2));
    router.define(alistBucketList, handler: alistBucketListHandler);
    router.define(alistBucketInformation,
        handler: alistBucketInformationHandler);
    router.define(alistFileExplorer, handler: alistFileExplorerHandler);
    router.define(alistFileInformation, handler: alistFileInformationHandler);
    router.define(pdfViewer, handler: pdfViewerHandler);
    router.define(webdavFileExplorer, handler: webdavFileExplorerHandler);
    router.define(webdavFileInformation, handler: webdavFileInformationHandler);
    router.define(baseUpDownloadManagePage, handler: baseDownloadFileHandler);
  }
}
