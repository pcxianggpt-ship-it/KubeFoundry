const SENSITIVE_ERROR_PATTERN = /password|passphrase|private[ _-]?key|secret|token|密码|口令|私钥|令牌/i;

export function containsSensitiveError(value) {
  return SENSITIVE_ERROR_PATTERN.test(String(value || ''));
}

export function safeErrorMessage(error, fallback = '请检查服务状态后重试。') {
  const message = error?.message || fallback;
  return containsSensitiveError(message)
    ? '服务返回了不可展示的敏感错误，请检查服务端日志。'
    : message;
}
