export function redisPasswordError(config) {
  const password = config?.password ?? '';
  if (password === '') return config?.has_password ? '' : '请输入 Redis / Sentinel 密码。';
  if (typeof password !== 'string' || !password.trim() || password.length > 256
      || /[\u0000-\u001f\u007f-\u009f]/.test(password)) {
    return '密码不能仅包含空白、包含控制字符或超过 256 个字符。';
  }
  return '';
}
