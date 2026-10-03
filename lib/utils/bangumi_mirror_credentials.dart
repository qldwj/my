// Bangumi mirror API credentials for the search signature flow.
// Release/PR CI injects them via --dart-define=KAZUMI_APPID / KAZUMI_KEY.
// 不硬编码明文默认值，避免源码暴露被恶意利用；未注入时为空。
const Map<String, String> bangumiMirrorCredentials = {
  'id': String.fromEnvironment('KAZUMI_APPID', defaultValue: ''),
  'value': String.fromEnvironment('KAZUMI_KEY', defaultValue: ''),
};
