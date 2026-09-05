// Bangumi mirror API credentials for the search signature flow.
// Release/PR CI injects them via --dart-define=KAZUMI_APPID / KAZUMI_KEY.
// 也为樱花服务器登录提供签名，硬编码值作为 CI 未注入时的回退
const Map<String, String> bangumiMirrorCredentials = {
  'id': String.fromEnvironment('KAZUMI_APPID',
      defaultValue: ''),
  'value': String.fromEnvironment('KAZUMI_KEY',
      defaultValue: ''),
};
