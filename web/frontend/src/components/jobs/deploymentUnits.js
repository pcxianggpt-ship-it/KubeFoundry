const TERMINAL_STEP_STATUSES = new Set(['success', 'failed', 'interrupted', 'skipped']);
const BLOCKED_REASONS = new Set(['JOB_ABORTED', 'COMPONENT_GROUP_PREVIOUS_STEP_FAILED']);

export function groupDeploymentUnits(steps = []) {
  const groups = new Map();
  [...steps].sort(compareSteps).forEach((step, index) => {
    const key = step.stage_key || `legacy-step-${step.id ?? index}`;
    if (!groups.has(key)) {
      groups.set(key, {
        key,
        name: step.stage_name || step.name || '任务步骤',
        order: positiveOrder(step.stage_order, index + 1),
        steps: []
      });
    }
    groups.get(key).steps.push(step);
  });
  return [...groups.values()]
    .sort((left, right) => left.order - right.order)
    .map((unit) => ({ ...unit, summary: summarizeDeploymentUnit(unit.steps) }));
}

export function summarizeDeploymentUnit(steps = []) {
  const total = steps.length;
  const completed = steps.filter((step) => TERMINAL_STEP_STATUSES.has(step.status)).length;
  const preverified = steps.filter(isPreverified).length;
  const blocked = steps.filter(isBlocked).length;
  const statuses = steps.map((step) => step.status);

  if (!total || statuses.every((status) => !status)) {
    return { status: 'planned', label: `${total} 个步骤`, tone: 'info', completed: 0, total, preverified };
  }
  if (statuses.some((status) => ['failed', 'interrupted'].includes(status))) {
    return { status: 'failed', label: '失败', tone: 'danger', completed, total, preverified };
  }
  if (statuses.includes('running')) {
    return { status: 'running', label: '执行中', tone: 'warning', completed, total, preverified };
  }
  if (statuses.includes('pending')) {
    return { status: 'pending', label: '等待执行', tone: 'info', completed, total, preverified };
  }
  if (preverified === total) {
    return { status: 'verified', label: '已验证并跳过', tone: 'success', completed, total, preverified };
  }
  if (blocked === total) {
    return { status: 'blocked', label: '已阻塞', tone: 'info', completed, total, preverified };
  }
  const label = preverified > 0 ? `成功 · 已验证跳过 ${preverified}` : '成功';
  return { status: 'success', label, tone: 'success', completed, total, preverified };
}

function compareSteps(left, right) {
  const stageOrder = positiveOrder(left.stage_order, left.order) - positiveOrder(right.stage_order, right.order);
  if (stageOrder) return stageOrder;
  return positiveOrder(left.step_order_in_stage, left.order)
    - positiveOrder(right.step_order_in_stage, right.order);
}

function positiveOrder(value, fallback = 1) {
  return Number(value) > 0 ? Number(value) : Number(fallback) || 1;
}

function isPreverified(step) {
  return step.status === 'skipped' && step.status_reason === 'PREVERIFY_SATISFIED';
}

function isBlocked(step) {
  return step.status === 'skipped' && BLOCKED_REASONS.has(step.status_reason);
}
