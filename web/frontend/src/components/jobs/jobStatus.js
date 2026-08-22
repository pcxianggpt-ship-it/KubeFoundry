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

export function stepStatusLabel(status, reason = '') {
  if (status !== 'skipped') return jobStatusLabel(status);
  if (reason === 'PREVERIFY_SATISFIED') return '已验证并跳过';
  if (['JOB_ABORTED', 'COMPONENT_GROUP_PREVIOUS_STEP_FAILED'].includes(reason)) return '因依赖跳过';
  return jobStatusLabel(status);
}

export function stepStatusTone(status, reason = '') {
  if (status === 'skipped' && reason === 'PREVERIFY_SATISFIED') return 'success';
  if (status === 'skipped') return 'info';
  return jobStatusTone(status);
}

export function verificationMessage(message = '') {
  if (message === 'PREVERIFY_SATISFIED') return '执行前验证通过，已安全跳过安装';
  if (message.startsWith('PREVERIFY_FAILED')) return '执行前验证失败';
  if (message.startsWith('POSTVERIFY_FAILED')) return '执行后验证失败';
  return message;
}

export function canResumeJob(job) {
  return ['install', 'component_install'].includes(job?.job_type)
    && ['failed', 'interrupted', 'partial_success'].includes(job?.status);
}

export function isTerminalJob(status) {
  return ['success', 'partial_success', 'failed', 'interrupted', 'canceled'].includes(status);
}
