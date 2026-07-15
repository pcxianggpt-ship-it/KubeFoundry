export const NODE_STATUS_LABELS = {
  pending: '待测试',
  running: '测试中',
  password_connecting: '密码连接中',
  key_installing: '配置免密中',
  key_verifying: '验证免密中',
  success: '测试成功',
  failed: '测试失败',
  stale: '需重新测试'
};

export function nodeStatusLabel(status) {
  return NODE_STATUS_LABELS[status] || '待测试';
}

export function nodeStatusTone(status) {
  if (status === 'success') return 'success';
  if (status === 'failed') return 'danger';
  if (['running', 'password_connecting', 'key_installing', 'key_verifying'].includes(status)) return 'warning';
  return 'info';
}
