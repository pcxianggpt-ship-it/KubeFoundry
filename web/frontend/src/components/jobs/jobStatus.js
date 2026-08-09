export const JOB_STATUS_LABELS = {
  pending: '等待执行',
  running: '执行中',
  success: '成功',
  partial_success: '部分成功',
  failed: '失败',
  interrupted: '已中断',
  canceled: '已取消',
  skipped: '已跳过'
};

export function jobStatusLabel(status) {
  return JOB_STATUS_LABELS[status] || '未开始';
}

export function jobStatusTone(status) {
  if (['success', 'partial_success'].includes(status)) return 'success';
  if (['failed', 'interrupted'].includes(status)) return 'danger';
  if (status === 'running') return 'warning';
  return 'info';
}

export function isTerminalJob(status) {
  return ['success', 'partial_success', 'failed', 'interrupted', 'canceled'].includes(status);
}
